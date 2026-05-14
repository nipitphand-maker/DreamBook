import 'package:sqflite_sqlcipher/sqflite.dart';

import 'family_key_service.dart';

/// Orchestrates `K_family` rotation. Local state only — the network
/// portion (re-encrypt remote rows, fan out via X25519) lands in C-2.
///
/// Crash safety: [beginRotation] records intent in `key_rotation_state`
/// BEFORE generating the new key. [resumeIfNeeded] finishes any
/// outstanding rotation on next app launch.
class KeyRotationService {
  KeyRotationService({required this.db, required this.familyKeys});

  final Database db;
  final FamilyKeyService familyKeys;

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
    await familyKeys.rotate(familyId: familyId);
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
