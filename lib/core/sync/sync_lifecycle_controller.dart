import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../crypto/crypto_envelope.dart';
import '../crypto/family_key_service.dart';
import '../db/database_provider.dart';
import '../families/family_provider.dart';
import '../providers/device_id_provider.dart';
import 'supabase_client_service.dart';
import 'supabase_sync_server.dart';
import 'sync_error_reporter.dart';
import 'sync_server.dart';
import 'sync_status_provider.dart';
import 'sync_trigger.dart';
import 'realtime_subscriber.dart';
import 'sync_worker.dart';

/// Lazy resolver for the [SyncStatusNotifier]. Provided as a closure so the
/// controller doesn't bind to one specific source (production passes a
/// closure over `Ref.read`; tests pass a closure over `ProviderContainer.read`).
typedef SyncStatusResolver = SyncStatusNotifier Function();

/// Triggers [SyncWorker.pullOnce] + [SyncWorker.pushOnce] when the app
/// returns from background. Pull-to-refresh on Home calls [syncNow] directly.
///
/// The controller pushes state transitions through [syncStatusProvider] so
/// the UI can render an inFlight spinner and lastSyncedAt timestamp without
/// the sync logic knowing anything about the widget tree.
class SyncLifecycleController extends WidgetsBindingObserver {
  SyncLifecycleController({
    required SyncStatusResolver resolveStatus,
    required this.worker,
  }) : _resolveStatus = resolveStatus;

  /// Convenience constructor for production: bind the controller to a
  /// provider's [Ref]. The closure captures `ref.read` so the same reader
  /// shape works in both test (ProviderContainer) and prod (Ref) callsites.
  SyncLifecycleController.fromRef({
    required Ref ref,
    required SyncWorker worker,
  }) : this(
          resolveStatus: () => ref.read(syncStatusProvider.notifier),
          worker: worker,
        );

  /// Convenience constructor for tests: accept a [ProviderContainer]
  /// directly so the test doesn't need to spin up a hosting provider.
  SyncLifecycleController.fromContainer({
    required ProviderContainer container,
    required SyncWorker worker,
  }) : this(
          resolveStatus: () => container.read(syncStatusProvider.notifier),
          worker: worker,
        );

  final SyncStatusResolver _resolveStatus;
  final SyncWorker worker;

  /// Lazily-allocated error reporter. Phase 2 (DV-6) will replace this with
  /// a Riverpod-provided singleton wired to Sentry + audit_events upload.
  /// For Phase 1 we keep it inline so the silent-catch fix lands without
  /// touching the provider graph.
  SyncErrorReporter? _reporter;

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      await syncNow(trigger: SyncTrigger.foreground);
    }
  }

  /// Fire-and-forget push after a local write. No-op in the no-op subclass.
  void schedulePush() => syncNow(trigger: SyncTrigger.postWrite).ignore();

  /// Run one pull+push cycle and update [syncStatusProvider] accordingly.
  /// Safe to call concurrently with the lifecycle hook — the notifier just
  /// overwrites state, and SyncWorker's own internal loops are serialised.
  Future<void> syncNow({SyncTrigger trigger = SyncTrigger.foreground}) async {
    // TODO(P2.28 BG-6): emit sync_background_started audit event for background trigger
    // Requires Supabase URL to be available in background isolate context.
    final status = _resolveStatus();
    status.startSync();
    try {
      await worker.pullOnce();
      await worker.pushOnce();
      status.completeSync(at: DateTime.now().toUtc());
      // TODO(P2.28 BG-6): emit sync_background_finished audit event with duration_ms
    } catch (e, st) {
      // Non-silent: SyncErrorReporter captures structured metadata for the
      // Phase 2 audit log + Sentry hookup. UI still gets the failure via
      // SyncStatusNotifier.failSync so the user sees the same banner.
      final reporter = _reporter ??= SyncErrorReporter();
      reporter.report(e, st);
      debugPrint('SyncWorker error [${e.runtimeType}]: $e');
      status.failSync(e);
    }
  }
}

/// SharedPreferences key under which the active family id is stored after
/// caregiver onboarding (Plan C). When absent, the device hasn't joined a
/// family yet and sync is a no-op.
const String kFamilyIdPrefsKey = 'family.id';

/// Controller variant used before caregiver onboarding has produced a
/// `family.id`. [syncNow] returns immediately and the
/// WidgetsBindingObserver lifecycle hook is a no-op — registering still
/// works, but pull-to-refresh + app-resume don't talk to Supabase.
class _NoOpSyncLifecycleController extends SyncLifecycleController {
  _NoOpSyncLifecycleController({required super.resolveStatus})
      : super(worker: _UnusedSyncWorker._());

  @override
  void schedulePush() {} // no family yet — intentional no-op

  @override
  Future<void> syncNow({SyncTrigger trigger = SyncTrigger.foreground}) async {
    // Intentionally empty — there is no family to sync against yet.
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    // Intentionally empty.
  }
}

/// Sentinel SyncWorker handed to the no-op controller. It is never invoked
/// (the no-op controller overrides both syncNow + didChangeAppLifecycleState),
/// but the parent constructor still requires a non-null worker reference.
class _UnusedSyncWorker extends SyncWorker {
  _UnusedSyncWorker._()
      : super(
          db: _UnusedDatabase(),
          server: _UnusedSyncServer(),
          familyKeys: FamilyKeyService.forTest(_UnusedSecureStorage()),
          envelope: CryptoEnvelope(),
          familyId: '',
          deviceFp: '',
        );
}

class _UnusedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No-op sync controller — worker should never run');
}

class _UnusedSyncServer implements SyncServer {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No-op sync controller — server should never run');
}

class _UnusedSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No-op sync controller — storage should never run');
}

/// The currently active family id as derived from [familyListProvider] +
/// the repository's prefs-backed active id. Returns null when no family is
/// active (pre-onboarding) or when the prefs string is empty.
///
/// Exposed as a dedicated provider so that consumers — most importantly
/// [syncLifecycleControllerProvider] — can [ref.watch] family-switch events
/// and rebind without requiring callers to remember to call
/// `ref.invalidate(syncLifecycleControllerProvider)` after a switch.
final currentFamilyIdProvider = Provider<String?>((ref) {
  // Depend on the list notifier so we rebuild when register/switchTo/remove
  // fires (each of those mutators reassigns `state`, triggering watchers).
  ref.watch(familyListProvider);
  final id = ref.watch(familyRepositoryProvider).activeId();
  if (id == null || id.isEmpty) return null;
  return id;
});

/// Returns a real [SyncLifecycleController] once SharedPreferences contains
/// a `family.id` AND the database is ready. Until then returns a
/// [_NoOpSyncLifecycleController] — pull-to-refresh + the
/// WidgetsBindingObserver attachment still succeed, they just don't talk to
/// Supabase.
///
/// Using [ref.watch] on [appDatabaseProvider] (instead of [ref.read]) means
/// Riverpod will rebuild this provider once the DB future resolves — fixing
/// the cold-start bug where the no-op was cached forever for the session.
///
/// Using [ref.watch] on [currentFamilyIdProvider] means Riverpod will
/// rebuild this provider when the user switches family, so the SyncWorker
/// and Realtime subscription are rebound to the new family id. The old
/// realtime subscription is torn down via the [ref.onDispose] hook below.
final syncLifecycleControllerProvider =
    Provider<SyncLifecycleController>((ref) {
  // Watch DB so this provider rebuilds once the DB future resolves.
  final dbAsync = ref.watch(appDatabaseProvider);
  // Watch the active family id so a switch triggers a full rebuild → new
  // SyncWorker bound to the new family, and ref.onDispose tears the old
  // Realtime channel down.
  final familyId = ref.watch(currentFamilyIdProvider);

  if (familyId == null || familyId.isEmpty) {
    return _NoOpSyncLifecycleController(
      resolveStatus: () => ref.read(syncStatusProvider.notifier),
    );
  }

  // DB may still be opening on cold start — fall back to no-op until ready.
  final db = dbAsync.value;
  if (db == null) {
    return _NoOpSyncLifecycleController(
      resolveStatus: () => ref.read(syncStatusProvider.notifier),
    );
  }

  // NOTE: AndroidOptions(encryptedSharedPreferences:true) is the spec-mandated
  // value but it's now deprecated upstream (flutter_secure_storage ^10
  // auto-migrates to custom ciphers; the flag is ignored). Use defaults.
  const secureStorage = FlutterSecureStorage();
  final familyKeys = FamilyKeyService(secureStorage);
  final deviceFp = ref.read(deviceIdProvider);
  final server = SupabaseSyncServer(SupabaseClientService.instance.client);

  final worker = SyncWorker(
    db: db,
    server: server,
    familyKeys: familyKeys,
    envelope: CryptoEnvelope(),
    familyId: familyId,
    deviceFp: deviceFp,
  );

  // Subscribe to Supabase Realtime so incoming rows from other devices
  // are applied immediately without waiting for the next app-resume sync.
  final realtime = RealtimeSubscriber(
    server: server,
    onIncomingRow: worker.onIncomingRow,
    onError: (_) => ref.read(syncStatusProvider.notifier).markRealtimeDegraded(),
  );
  realtime.connect(familyId: familyId).ignore();
  ref.onDispose(realtime.disconnect);

  return SyncLifecycleController.fromRef(ref: ref, worker: worker);
});
