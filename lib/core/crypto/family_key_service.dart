import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A family key snapshot loaded from secure storage.
class FamilyKey {
  const FamilyKey({required this.bytes, required this.keyVersion});

  final Uint8List bytes;
  final int keyVersion;
}

/// Holds `K_family` per family. Production uses [FlutterSecureStorage];
/// tests inject a fake via [FamilyKeyService.forTest].
///
/// Storage shape: one entry per family at
///   `dreambook_family_key_v1::${familyId}` → base64Url(bytes) + '|' + keyVersion.
class FamilyKeyService {
  FamilyKeyService(this._storage);

  /// Test-only constructor that accepts any storage with the same
  /// read/write/delete surface (e.g. InMemorySecureStorage).
  FamilyKeyService.forTest(dynamic storage) : _storage = storage;

  static const String _aliasPrefix = 'dreambook_family_key_v1::';
  static const int _kKeyLength = 32;

  // Typed as dynamic to allow both FlutterSecureStorage and the test fake
  // without bringing the fake into production code paths.
  final dynamic _storage;

  String _alias(String familyId) => '$_aliasPrefix$familyId';

  /// Generates a fresh 32-byte key, persists it, returns the bytes.
  Future<Uint8List> generate({
    required String familyId,
    required int keyVersion,
  }) async {
    final rng = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(_kKeyLength, (_) => rng.nextInt(256)),
    );
    await _write(familyId: familyId, bytes: bytes, keyVersion: keyVersion);
    return bytes;
  }

  /// Returns the stored key or null. Returns null on read errors too —
  /// caller's responsibility to decide whether to wipe + re-handshake.
  Future<FamilyKey?> read({required String familyId}) async {
    try {
      final raw = await _storage.read(key: _alias(familyId)) as String?;
      if (raw == null) return null;
      final parts = raw.split('|');
      if (parts.length != 2) return null;
      final bytes = base64Url.decode(parts[0]);
      final ver = int.tryParse(parts[1]);
      if (ver == null) return null;
      return FamilyKey(bytes: Uint8List.fromList(bytes), keyVersion: ver);
    } catch (e) {
      debugPrint('[family_key] read failed for $familyId: $e');
      return null;
    }
  }

  /// Generates a new key and stores it with `keyVersion = old + 1`.
  Future<FamilyKey> rotate({required String familyId}) async {
    final current = await read(familyId: familyId);
    final nextVersion = (current?.keyVersion ?? 0) + 1;
    final bytes = await generate(familyId: familyId, keyVersion: nextVersion);
    return FamilyKey(bytes: bytes, keyVersion: nextVersion);
  }

  /// Installs an externally-derived 32-byte key (e.g. from key_distribution
  /// after a rotation). Replaces any existing entry for [familyId].
  Future<void> install({
    required String familyId,
    required Uint8List bytes,
    required int keyVersion,
  }) async {
    if (bytes.length != _kKeyLength) {
      throw ArgumentError('K_family must be exactly $_kKeyLength bytes');
    }
    await _write(familyId: familyId, bytes: bytes, keyVersion: keyVersion);
  }

  /// Removes the entry. Called on revocation/wipe paths.
  Future<void> clear({required String familyId}) async {
    await _storage.delete(key: _alias(familyId));
  }

  Future<void> _write({
    required String familyId,
    required Uint8List bytes,
    required int keyVersion,
  }) async {
    final encoded = '${base64Url.encode(bytes)}|$keyVersion';
    await _storage.write(key: _alias(familyId), value: encoded);
  }
}
