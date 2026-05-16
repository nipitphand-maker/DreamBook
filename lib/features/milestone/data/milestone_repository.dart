import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/models/milestone_achievement.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

class MilestoneRepository {
  MilestoneRepository(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  Future<Database> get _db => _ref.read(appDatabaseProvider.future);

  Future<List<MilestoneAchievement>> allForBaby(String babyId) async {
    final db = await _db;
    final rows = await db.query(
      'milestone_achievement',
      where: 'baby_id = ? AND deleted_at IS NULL',
      whereArgs: [babyId],
      orderBy: 'achieved_on ASC',
    );
    return rows.map(MilestoneAchievement.fromRow).toList(growable: false);
  }

  Future<void> markAchieved(MilestoneAchievement achievement) async {
    final db = await _db;
    final record = achievement.copyWith(
      id: achievement.id.isEmpty ? _uuid.v4() : achievement.id,
    );
    await db.transaction((txn) async {
      await txn.insert(
        'milestone_achievement',
        record.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'sync_state',
        {
          'record_id': record.id,
          'table_name': 'milestone_achievement',
          'version': record.version,
          'updated_at': record.updatedAt.toIso8601String(),
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> unmark(String achievementId) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      final affected = await txn.rawUpdate(
        '''
        UPDATE milestone_achievement
        SET deleted_at = ?,
            updated_at = ?,
            version    = version + 1
        WHERE id = ?
        ''',
        [now, now, achievementId],
      );
      if (affected == 0) return;

      final newVersion = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT version FROM milestone_achievement WHERE id = ?',
              [achievementId],
            ),
          ) ??
          1;

      await txn.insert(
        'sync_state',
        {
          'record_id': achievementId,
          'table_name': 'milestone_achievement',
          'version': newVersion,
          'updated_at': now,
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }
}

final milestoneRepositoryProvider =
    Provider<MilestoneRepository>(MilestoneRepository.new);
