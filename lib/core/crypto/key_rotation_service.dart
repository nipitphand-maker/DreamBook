import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../sync/sync_server.dart';
import 'crypto_envelope.dart';
import 'family_key_service.dart';

/// Orchestrates `K_family` rotation. C-1 implemented the local-only flow
/// (begin/complete/resume). C-2 adds [rotateRevokeAndFanOut] which performs
/// the server-side revoke + X25519 fan-out to surviving devices.
///
/// Crash safety: [beginRotation] records intent in `key_rotation_state`
/// BEFORE generating the new key. [resumeIfNeeded] finishes any
/// outstanding rotation on next app launch.
class KeyRotationService {
  KeyRotationService({
    required this.db,
    required this.familyKeys,
    this.server,
    this.callerDeviceFp = '',
    this.ourKeyPair,
  });

  final Database db;
  final FamilyKeyService familyKeys;

  /// Optional — only required by [rotateRevokeAndFanOut]. Local-only
  /// rotation paths (begin/complete/resume) don't need a server.
  final SyncServer? server;

  /// This device's fingerprint (used as the auth identity for the server
  /// revoke call). Empty when [server] is null.
  final String callerDeviceFp;

  /// This device's X25519 key pair, used to derive the per-survivor
  /// shared secret during fan-out. Required when [server] is non-null.
  final SimpleKeyPair? ourKeyPair;

  /// Begins rotation: bumps target version in `key_rotation_state`.
  /// Idempotent — calling twice in a row leaves a single row.
  Future<void> beginRotation({required String familyId}) async {
    final meta = await _readFamilyMetadata(familyId);
    final target = meta + 1;
    await db.insert(
      'key_rotation_state',
      {
        'family_id': familyId,
        'target_key_version': target,
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'last_processed_row': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Generates the new K_family, switches local state, and clears
  /// `key_rotation_state`. Bumps `family_metadata.current_key_version`.
  Future<void> completeRotation({required String familyId}) async {
    final state = await _readRotationState(familyId);
    if (state == null) {
      throw StateError('No rotation in progress for $familyId');
    }
    // If the caller already rotated the local K_family (e.g. inside
    // [rotateRevokeAndFanOut]), don't double-rotate. We detect that by
    // checking whether the secure-storage key already matches the target.
    final stored = await familyKeys.read(familyId: familyId);
    if (stored == null || stored.keyVersion < state) {
      await familyKeys.rotate(familyId: familyId);
    }
    await db.transaction((txn) async {
      await txn.update(
        'family_metadata',
        {'current_key_version': state},
        where: 'id = ?',
        whereArgs: [familyId],
      );
      await txn.delete(
        'key_rotation_state',
        where: 'family_id = ?',
        whereArgs: [familyId],
      );
    });
  }

  /// Called on app launch. If an interrupted rotation exists, finish it.
  Future<void> resumeIfNeeded({required String familyId}) async {
    final state = await _readRotationState(familyId);
    if (state == null) return;
    await completeRotation(familyId: familyId);
  }

  /// Full network rotation: revoke [targetDeviceFp] server-side, generate
  /// a new K_family locally, fan it out via X25519 to every surviving
  /// device, then finalize. Crash-safe — if any step after
  /// [beginRotation] fails, [resumeIfNeeded] finishes on next launch.
  ///
  /// Requires [server] and [ourKeyPair] to have been provided at
  /// construction time.
  Future<void> rotateRevokeAndFanOut({
    required String familyId,
    required String targetDeviceFp,
  }) async {
    final s = server;
    final kp = ourKeyPair;
    if (s == null || kp == null) {
      throw StateError(
        'rotateRevokeAndFanOut requires server and ourKeyPair',
      );
    }

    // 1. Record intent locally FIRST so a crash after revokeCaregiver is
    //    recoverable: resumeIfNeeded on next launch will finish the rotation.
    await beginRotation(familyId: familyId);

    // 2. Atomic server-side revoke + key-version bump.
    final result = await s.revokeCaregiver(
      callerDeviceFp: callerDeviceFp,
      targetDeviceFp: targetDeviceFp,
    );
    final newVersion = result.newKeyVersion;

    // 3. Generate new K_family locally.
    await familyKeys.rotate(familyId: familyId);
    final newKey = await familyKeys.read(familyId: familyId);
    if (newKey == null) {
      throw StateError('FamilyKeyService.rotate did not persist new key');
    }
    final newKeyBytes = newKey.bytes;

    // 4. X25519 fan-out: wrap K_family_vN (AES-GCM-256 inside
    //    [CryptoEnvelope]) for each survivor.
    final envelope = CryptoEnvelope();
    final x25519 = X25519();
    for (final survivor in result.survivors) {
      final pub = SimplePublicKey(
        List<int>.from(survivor.devicePubKey),
        type: KeyPairType.x25519,
      );
      final shared = await x25519.sharedSecretKey(
        keyPair: kp,
        remotePublicKey: pub,
      );
      final aad = utf8.encode('$familyId|$newVersion');
      final wrapped = await envelope.seal(newKeyBytes, shared, aad);
      await s.insertKeyDistribution(
        familyId: familyId,
        recipientDeviceFp: survivor.deviceFp,
        keyVersion: newVersion,
        wrappedKey: Uint8List.fromList(wrapped),
      );
    }

    // 5. Finalize locally.
    await completeRotation(familyId: familyId);
  }

  Future<int> _readFamilyMetadata(String familyId) async {
    final rows = await db.query(
      'family_metadata',
      where: 'id = ?',
      whereArgs: [familyId],
    );
    if (rows.isEmpty) {
      throw StateError('No family_metadata row for $familyId');
    }
    return rows.first['current_key_version'] as int;
  }

  Future<int?> _readRotationState(String familyId) async {
    final rows = await db.query(
      'key_rotation_state',
      where: 'family_id = ?',
      whereArgs: [familyId],
    );
    if (rows.isEmpty) return null;
    return rows.first['target_key_version'] as int;
  }
}
