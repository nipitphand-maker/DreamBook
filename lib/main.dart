import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'core/background/workmanager_sync.dart';
import 'core/crypto/device_identity_service.dart';
import 'core/env.dart';
import 'core/providers/device_id_provider.dart';
import 'core/providers/shared_preferences_provider.dart';
import 'core/services/notification_service.dart';
import 'core/services/secure_key_service.dart';
import 'core/sync/supabase_client_service.dart';

const _kDeviceIdKey = 'device.id';

Future<String> _getOrCreateDeviceId(SharedPreferences prefs) async {
  var id = prefs.getString(_kDeviceIdKey);
  if (id == null) {
    id = const Uuid().v4();
    await prefs.setString(_kDeviceIdKey, id);
  }
  return id;
}

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

  // 1. Ensure encryption key exists (Keychain / EncryptedSharedPreferences).
  await SecureKeyService.getOrCreateDbKey();

  // 2. Notifications init (channels, timezone db).
  await NotificationService.init();

  // 3. SharedPreferences (sync provider override).
  final prefs = await SharedPreferences.getInstance();

  // 4. Stable device_id for caregiver attribution (Plan C uses for invite handshake).
  final deviceId = await _getOrCreateDeviceId(prefs);

  // 5. Supabase: initialise the client + ensure anonymous session, then
  //    create the device-level Ed25519 keypair used for the invite
  //    handshake. Missing .env (no secrets bundled) skips Supabase init
  //    so local-only flows still work.
  const secureStorage = FlutterSecureStorage();
  final env = await _loadEnv();
  if (env != null) {
    try {
      await SupabaseClientService.initialize(env: env, storage: secureStorage);
      await SupabaseClientService.instance.ensureAnonymousSession();
      await DeviceIdentityService(secureStorage).getOrCreate();
    } catch (_) {
      // Supabase init or anon-auth failed (e.g. provider disabled, no network).
      // App still boots in local-only mode; caregiver screens surface the
      // error themselves rather than blocking startup.
    }
  }

  // 6. WorkManager — inexact periodic background sync. Safe to call every
  //    app launch; WorkManager deduplicates by unique task name.
  //    Wrapped in try/catch so unit tests (no Android runtime) don't crash.
  try {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: kDebugMode);
    await registerBackgroundSync();
  } catch (_) {
    // WorkManager init failed (e.g. unit-test host, no Android runtime).
    // App still boots in local-only mode.
  }

  // 7. RevenueCat — Android public API key. Wrapped in try/catch so missing
  //    Play Services on emulator / dev devices never blocks app boot.
  //    `isPremiumProvider` handles the not-configured case via try/catch too.
  try {
    await Purchases.setLogLevel(LogLevel.error);
    await Purchases.configure(
      PurchasesConfiguration('goog_AjoINZEXfCpIXYfKgLbWXTPnCdt'),
    );
  } catch (_) {
    // RC init failed (e.g. emulator without Play Services). App still boots;
    // premium gates will resolve to `false` and paywall will surface an
    // empty offering rather than crashing.
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        deviceIdProvider.overrideWithValue(deviceId),
      ],
      child: const DreamBookApp(),
    ),
  );
}
