import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'core/background/workmanager_sync.dart';
import 'core/crypto/device_identity_service.dart';
import 'core/env.dart';
import 'core/observability/boot_diagnostics.dart';
import 'core/observability/sentry_init.dart';
import 'core/providers/device_id_provider.dart';
import 'core/providers/shared_preferences_provider.dart';
import 'core/services/notification_service.dart';
import 'core/services/secure_key_service.dart';
import 'core/sync/supabase_client_service.dart';

/// Loads the bundled `.env` asset. Returns null when the asset is missing
/// (e.g. CI / fresh checkout without secrets) so the app can still boot —
/// the sync layer detects no Supabase client and falls back to local-only.
Future<Env?> _loadEnv() async {
  try {
    final content = await rootBundle.loadString('assets/.env');
    return Env.fromString(content);
  } catch (_) {
    return null;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── CRITICAL PATH ─────────────────────────────────────────────────────
  // Only steps required before ProviderScope can render the first frame.
  // Anything that touches the network MUST go to the deferred phase below.

  // 1. Encryption key (Keychain / EncryptedSharedPreferences). Required
  //    because the DB is encrypted with it and the home screen reads from
  //    the DB on first build.
  await SecureKeyService.getOrCreateDbKey();

  // 2. SharedPreferences — needed for the prefs override below.
  final prefs = await SharedPreferences.getInstance();

  // 3. Device Ed25519 keypair — produces the deviceFp override that RLS
  //    relies on for `family_devices.device_fp` lookups.
  const secureStorage = FlutterSecureStorage();
  final deviceIdentity = await DeviceIdentityService(secureStorage).getOrCreate();
  final deviceId = await deviceIdentity.fingerprintHex();
  if (kDebugMode) {
    debugPrint('[boot] deviceFp=$deviceId pubKeyLen=${deviceIdentity.publicKeyBytes.length}');
  }

  // 4. Bundled env (file-only I/O, no network). Safe in the critical path.
  final env = await _loadEnv();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // Must match SHA-256(pubKey)[0:16] hex — RLS contract with family_devices.device_fp.
        deviceIdProvider.overrideWithValue(deviceId),
      ],
      child: const DreamBookApp(),
    ),
  );

  // ── DEFERRED PATH ─────────────────────────────────────────────────────
  // Runs after the first frame is on screen. Network calls, plugin
  // initialisation, and any SDK that can fail without blocking a logged
  // event live here. Errors record into BootDiagnostics so the user can
  // tell support "Supabase init failed" instead of "app feels broken."
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_secondaryInit(env: env, prefs: prefs, secureStorage: secureStorage));
  });
}

Future<void> _secondaryInit({
  required Env? env,
  required SharedPreferences prefs,
  required FlutterSecureStorage secureStorage,
}) async {
  // Notifications: channel registration + timezone db load. Wrapped so a
  // missing plugin (unit-test host) never blocks subsequent steps.
  try {
    await NotificationService.init();
  } catch (e, st) {
    BootDiagnostics.instance.recordError('notifications', e, st);
  }

  // Supabase init + anon sign-in (THE network call). Failure is non-fatal:
  // local features keep working; share/sync screens surface a banner.
  if (env != null) {
    try {
      await SupabaseClientService.initialize(env: env, storage: secureStorage);
      await SupabaseClientService.instance.ensureAnonymousSession();
    } catch (e, st) {
      BootDiagnostics.instance.recordError('supabase', e, st);
    }
  }

  // WorkManager: registers the periodic background sync. Safe to call every
  // launch; deduplicated by unique task name.
  try {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: kDebugMode);
    await registerBackgroundSync();
  } catch (e, st) {
    BootDiagnostics.instance.recordError('workmanager', e, st);
  }

  // RevenueCat. Premium gate already tolerates a missing config via
  // `isPremiumProvider`'s cached-fallback path.
  try {
    await Purchases.setLogLevel(LogLevel.error);
    await Purchases.configure(
      PurchasesConfiguration('goog_AjoINZEXfCpIXYfKgLbWXTPnCdt'),
    );
  } catch (e, st) {
    BootDiagnostics.instance.recordError('revenuecat', e, st);
  }

  // Sentry — opt-in only. DSN supplied via --dart-define=SENTRY_DSN=...
  // at build time (never bundled in the APK asset).
  final sentryOptIn = prefs.getBool('sentry_opt_in') ?? false;
  if (sentryOptIn && kSentryDsn.isNotEmpty) {
    try {
      await initSentry(dsn: kSentryDsn);
    } catch (e, st) {
      BootDiagnostics.instance.recordError('sentry', e, st);
    }
  }
}
