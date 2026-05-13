import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureKeyService {
  SecureKeyService._();

  static const _dbKeyAlias = 'dreambook_db_key_v1';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Returns the encryption key for sqflite_sqlcipher. Generates one on
  /// first call and stores it in Keychain (iOS) / EncryptedSharedPreferences
  /// (Android). On rare KeyStore corruption, wipes and regenerates — old DB
  /// becomes unreadable, which is recoverable (re-onboarding) but logged.
  static Future<String> getOrCreateDbKey() async {
    try {
      var key = await _storage.read(key: _dbKeyAlias);
      if (key == null) {
        key = _makeKey();
        await _storage.write(key: _dbKeyAlias, value: key);
      }
      return key;
    } catch (_) {
      final newKey = _makeKey();
      try {
        await _storage.deleteAll();
        await _storage.write(key: _dbKeyAlias, value: newKey);
      } catch (_) {/* swallow — return key anyway */}
      return newKey;
    }
  }

  static String _makeKey() {
    final r = Random.secure();
    final bytes = List<int>.generate(32, (_) => r.nextInt(256));
    // Strip '=' padding so the key matches url-safe-base64 alphabet only.
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
