import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Local persistence for the Caregiver entity.
///
/// Plan B is single-device, so caregiver management is intentionally minimal:
/// the only writer is `getOrCreateSelf`, called once on first launch to
/// represent the device owner ("Me"). Invites, roles, and revocation arrive
/// in Plan C.
class CaregiverRepository {
  CaregiverRepository(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  Future<Database> get _db => _ref.read(appDatabaseProvider.future);

  /// Get or create the "self" caregiver — the device owner. Identified by
  /// `(displayName, deviceId)`; the persistent deviceId comes from
  /// SharedPreferences (callers are responsible for obtaining it).
  ///
  /// Idempotent: subsequent calls return the existing row without touching
  /// `sync_state` (so a previously-synced "self" row stays clean).
  Future<Caregiver> getOrCreateSelf({
    required String deviceId,
    String displayName = 'Me',
  }) async {
    final db = await _db;
    final existing = await db.query(
      'caregiver',
      where: 'display_name = ? AND device_id = ? AND deleted_at IS NULL',
      whereArgs: [displayName, deviceId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return Caregiver.fromRow(existing.first);
    }

    final now = DateTime.now().toUtc();
    final caregiver = Caregiver(
      id: _uuid.v4(),
      displayName: displayName,
      deviceId: deviceId,
      joinedAt: now,
      createdAt: now,
      updatedAt: now,
    );

    await db.transaction((txn) async {
      await txn.insert('caregiver', caregiver.toRow());
      await txn.insert(
        'sync_state',
        {
          'record_id': caregiver.id,
          'table_name': 'caregiver',
          'version': caregiver.version,
          'updated_at': now.toIso8601String(),
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    return caregiver;
  }

  /// All active caregivers (not revoked, not deleted), ordered by joined_at ASC.
  Future<List<Caregiver>> listActive() async {
    final db = await _db;
    final rows = await db.query(
      'caregiver',
      where: 'revoked_at IS NULL AND deleted_at IS NULL',
      orderBy: 'joined_at ASC',
    );
    return rows.map(Caregiver.fromRow).toList(growable: false);
  }
}

final caregiverRepositoryProvider =
    Provider<CaregiverRepository>(CaregiverRepository.new);
