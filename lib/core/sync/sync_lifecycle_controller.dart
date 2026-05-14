import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_status_provider.dart';
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

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      await syncNow();
    }
  }

  /// Run one pull+push cycle and update [syncStatusProvider] accordingly.
  /// Safe to call concurrently with the lifecycle hook — the notifier just
  /// overwrites state, and SyncWorker's own internal loops are serialised.
  Future<void> syncNow() async {
    final status = _resolveStatus();
    status.startSync();
    try {
      await worker.pullOnce();
      await worker.pushOnce();
      status.completeSync(at: DateTime.now().toUtc());
    } catch (e) {
      status.failSync(e);
    }
  }
}

/// Placeholder provider so [HomeScreen]'s pull-to-refresh + main.dart wiring
/// compile against a stable API surface. Task 16 will override this in the
/// app root with a real instance constructed from the active
/// [SyncWorker] + [SupabaseSyncServer].
final syncLifecycleControllerProvider = Provider<SyncLifecycleController>((ref) {
  throw UnimplementedError('syncLifecycleControllerProvider not wired yet');
});
