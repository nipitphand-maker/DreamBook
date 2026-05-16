import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/models/temp_reading.dart';
import 'package:dreambook/core/sync/sync_lifecycle_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

class TempReadingRepository {
  TempReadingRepository(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  Future<Database> get _db => _ref.read(appDatabaseProvider.future);

  Future<void> insert(TempReading r) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert('temp_reading', r.toRow());
      await txn.insert(
        'sync_state',
        {
          'record_id': r.id,
          'table_name': 'temp_reading',
          'version': r.version,
          'updated_at': r.updatedAt.toUtc().toIso8601String(),
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    _ref.invalidate(tempReadingsProvider(r.babyId));
    _ref.read(syncLifecycleControllerProvider).schedulePush();
  }

  Future<void> softDelete(String id) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final affected = await txn.rawUpdate(
        '''
        UPDATE temp_reading
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
              'SELECT version FROM temp_reading WHERE id = ?',
              [id],
            ),
          ) ??
          1;

      await txn.insert(
        'sync_state',
        {
          'record_id': id,
          'table_name': 'temp_reading',
          'version': newVersion,
          'updated_at': now,
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    _ref.read(syncLifecycleControllerProvider).schedulePush();
  }

  Future<List<TempReading>> forBaby(String babyId, {int limit = 50}) async {
    final db = await _db;
    final rows = await db.query(
      'temp_reading',
      where: 'baby_id = ? AND deleted_at IS NULL',
      whereArgs: [babyId],
      orderBy: 'taken_at DESC',
      limit: limit,
    );
    return rows.map(TempReading.fromRow).toList(growable: false);
  }

  Future<List<TempReading>> forBabyDateRange(
    String babyId,
    DateTime from,
    DateTime to,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'temp_reading',
      where:
          'baby_id = ? AND deleted_at IS NULL AND taken_at >= ? AND taken_at < ?',
      whereArgs: [
        babyId,
        from.toUtc().toIso8601String(),
        to.toUtc().toIso8601String(),
      ],
      orderBy: 'taken_at ASC',
    );
    return rows.map(TempReading.fromRow).toList(growable: false);
  }

  static String newId() => _uuid.v4();
}

final tempReadingRepositoryProvider =
    Provider<TempReadingRepository>(TempReadingRepository.new);

final tempReadingsProvider =
    FutureProvider.family<List<TempReading>, String>((ref, babyId) {
  return ref.read(tempReadingRepositoryProvider).forBaby(babyId);
});
