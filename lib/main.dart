import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/providers/shared_preferences_provider.dart';
import 'core/services/notification_service.dart';
import 'core/services/secure_key_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Ensure encryption key exists (Keychain / EncryptedSharedPreferences).
  await SecureKeyService.getOrCreateDbKey();

  // 2. Notifications init (channels, timezone db).
  await NotificationService.init();

  // 3. SharedPreferences (sync provider override).
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const DreamBookApp(),
    ),
  );
}
