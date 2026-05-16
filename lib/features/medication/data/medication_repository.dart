import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/sync/sync_lifecycle_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

class MedicationRepository {
  MedicationRepository(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  Future<Database> get _db => _ref.read(appDatabaseProvider.future);

  Future<void> insert(MedicationDose d) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert('medication_dose', d.toRow());
      await txn.insert(
        'sync_state',
        {
          'record_id': d.id,
          'table_name': 'medication_dose',
          'version': d.version,
          'updated_at': d.updatedAt.toUtc().toIso8601String(),
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    _ref.read(syncLifecycleControllerProvider).schedulePush();
  }

  Future<void> softDelete(String id) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      final affected = await txn.rawUpdate(
        '''
        UPDATE medication_dose
        SET deleted_at = ?,
            updated_at = ?,
            version    = version + 1
        WHERE id = ?
        ''',
        [now, now, id],
      );
      if (affected == 0) return;

      final newVersion = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT version FROM medication_dose WHERE id = ?',
              [id],
            ),
          ) ??
          1;

      await txn.insert(
        'sync_state',
        {
          'record_id': id,
          'table_name': 'medication_dose',
          'version': newVersion,
          'updated_at': now,
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _ref.read(syncLifecycleControllerProvider).schedulePush();
  }

  Future<List<MedicationDose>> forBabyToday(
    String babyId,
    DateTime logicalDayStart,
  ) async {
    final db = await _db;
    final start = logicalDayStart.toUtc().toIso8601String();
    final end = logicalDayStart
        .add(const Duration(days: 1))
        .toUtc()
        .toIso8601String();
    final rows = await db.query(
      'medication_dose',
      where:
          'baby_id = ? AND deleted_at IS NULL AND given_at >= ? AND given_at < ?',
      whereArgs: [babyId, start, end],
      orderBy: 'given_at DESC',
    );
    return rows.map(MedicationDose.fromRow).toList(growable: false);
  }

  Future<List<MedicationDose>> forBabyDateRange(
    String babyId,
    DateTime from,
    DateTime to,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'medication_dose',
      where:
          'baby_id = ? AND deleted_at IS NULL AND given_at >= ? AND given_at < ?',
      whereArgs: [
        babyId,
        from.toUtc().toIso8601String(),
        to.toUtc().toIso8601String(),
      ],
      orderBy: 'given_at ASC',
    );
    return rows.map(MedicationDose.fromRow).toList(growable: false);
  }

  Future<MedicationDose?> lastDoseForBaby(String babyId) async {
    final db = await _db;
    final rows = await db.query(
      'medication_dose',
      where: 'baby_id = ? AND deleted_at IS NULL',
      whereArgs: [babyId],
      orderBy: 'given_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MedicationDose.fromRow(rows.first);
  }

  static String generateId() => _uuid.v4();
}

final medicationRepositoryProvider =
    Provider<MedicationRepository>(MedicationRepository.new);
