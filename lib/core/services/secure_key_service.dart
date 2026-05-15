import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

class SecureKeyService {
  SecureKeyService._();

  static const _dbKeyAlias = 'dreambook_db_key_v1';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      // first_unlock_this_device: accessible after first unlock; does not
      // migrate to new device (device-bound, per spec §6.1 item 2).
      // ignore: prefer_const_constructors
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// Returns the encryption key for sqflite_sqlcipher. Generates one on
  /// first call and stores it in Keychain (iOS) / EncryptedSharedPreferences
  /// (Android).
  ///
  /// On KeyStore failure the behaviour depends on whether the DB file already
  /// exists:
  ///
  /// - **DB file absent** (first install or already wiped): safe to generate a
  ///   new key — no data exists to lose.
  /// - **DB file present**: the key is inaccessible but real user data is on
  ///   disk. Wiping would silently destroy data. Instead we throw a descriptive
  ///   exception so the app can surface a recovery screen rather than silently
  ///   data-wiping (e.g. device locked at boot on Android, Secure Enclave
  ///   unavailable).
  static Future<String> getOrCreateDbKey() async {
    try {
      var key = await _storage.read(key: _dbKeyAlias);
      if (key == null) {
        key = _makeKey();
        await _storage.write(key: _dbKeyAlias, value: key);
      }
      return key;
    } catch (_) {
      // Determine whether this device already has a database on disk.
      final dbExists = await _dbFileExists();
      if (dbExists) {
        // The DB file is present but we cannot read the encryption key.
        // This typically means the device was still locked at cold-start
        // (Android Direct Boot / Keystore unavailable). Do NOT wipe data.
        throw StateError(
          'Device locked or key unavailable — cannot open database. '
          'Please unlock the device and relaunch the app.',
        );
      }

      // No DB file on disk — safe to generate a fresh key.
      final newKey = _makeKey();
      try {
        await _storage.deleteAll();
        await _storage.write(key: _dbKeyAlias, value: newKey);
      } catch (_) {/* swallow — return key anyway */}
      return newKey;
    }
  }

  /// Returns true when the sqflite database file already exists on disk.
  static Future<bool> _dbFileExists() async {
    try {
      final dir = await getDatabasesPath();
      final path = p.join(dir, 'dreambook.db');
      return File(path).existsSync();
    } catch (_) {
      // Cannot determine — assume absent (safer than a false positive that
      // would prevent key regeneration on a genuinely fresh install).
      return false;
    }
  }

  static String _makeKey() {
    final r = Random.secure();
    final bytes = List<int>.generate(32, (_) => r.nextInt(256));
    // Strip '=' padding so the key matches url-safe-base64 alphabet only.
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
