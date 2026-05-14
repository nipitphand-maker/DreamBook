import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'app.dart';
import 'core/providers/device_id_provider.dart';
import 'core/providers/shared_preferences_provider.dart';
import 'core/services/notification_service.dart';
import 'core/services/secure_key_service.dart';

const _kDeviceIdKey = 'device.id';

Future<String> _getOrCreateDeviceId(SharedPreferences prefs) async {
  var id = prefs.getString(_kDeviceIdKey);
  if (id == null) {
    id = const Uuid().v4();
    await prefs.setString(_kDeviceIdKey, id);
  }
  return id;
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

  // TODO(c2): register ref.read(syncLifecycleControllerProvider) as
  // WidgetsBindingObserver in the app root widget once Task 16 wires
  // SyncWorker + SupabaseSyncServer + caregiver-onboarded family/device.
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
