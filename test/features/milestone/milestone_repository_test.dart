import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/db/migrations/m001_initial.dart';
import 'package:dreambook/core/db/migrations/m002_v2.dart';
import 'package:dreambook/core/db/migrations/m003_v3.dart';
import 'package:dreambook/core/db/migrations/m004_v4.dart';
import 'package:dreambook/core/db/migrations/m005_daily_note.dart';
import 'package:dreambook/core/db/migrations/m006_sync_written_by.dart';
import 'package:dreambook/core/db/migrations/m007_sync_cursors.dart';
import 'package:dreambook/core/db/migrations/m008_milestone.dart';
import 'package:dreambook/core/db/migrations/m009_temp_reading.dart';
import 'package:dreambook/core/db/migrations/m010_medication.dart';
import 'package:dreambook/core/db/migrations/migrations.dart';
import 'package:dreambook/core/models/milestone_achievement.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/features/milestone/data/milestone_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  late Database db;
  late ProviderContainer container;
  late MilestoneRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 10,
        onCreate: (d, _) async {
          await Migrations([
            m001Initial,
            m002V2,
            m003V3,
            m004V4,
            m005DailyNote,
            m006SyncWrittenBy,
            m007SyncCursors,
            m008Milestone,
            m009TempReading,
            m010Medication,
          ]).runAll(d);
        },
      ),
    );
    await db.execute('PRAGMA foreign_keys = ON');
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWith((_) async => db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    repo = container.read(milestoneRepositoryProvider);
    // Insert baby FK
    await db.insert('baby', {
      'id': 'b1',
      'name': 'Mali',
      'dob': '2026-03-01',
      'preferred_unit': 'oz',
      'created_at': '2026-05-13T00:00:00.000Z',
      'updated_at': '2026-05-13T00:00:00.000Z',
      'version': 1,
    });
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  // ---------------------------------------------------------------------------
  // markAchieved()
  // ---------------------------------------------------------------------------

  test('markAchieved() persists row with all required fields', () async {
    final achievedOn = DateTime.utc(2026, 5, 10, 8);
    final now = DateTime.utc(2026, 5, 13, 9);
    final achievement = MilestoneAchievement(
      id: 'ach-1',
      babyId: 'b1',
      milestoneId: 'ms-smile',
      achievedOn: achievedOn,
      note: 'first smile!',
      version: 1,
      deletedAt: null,
      updatedAt: now,
    );

    await repo.markAchieved(achievement);

    final rows = await db.query(
      'milestone_achievement',
      where: 'id = ?',
      whereArgs: ['ach-1'],
    );
    expect(rows.length, 1);
    expect(rows.first['baby_id'], 'b1');
    expect(rows.first['milestone_id'], 'ms-smile');
    expect(rows.first['achieved_on'], isNotNull);
    expect(rows.first['version'], 1);
    expect(rows.first['deleted_at'], isNull);
  });

  test('markAchieved() writes sync_state row with dirty=1 and version=1',
      () async {
    final now = DateTime.utc(2026, 5, 13, 9);
    final achievement = MilestoneAchievement(
      id: 'ach-2',
      babyId: 'b1',
      milestoneId: 'ms-crawl',
      achievedOn: DateTime.utc(2026, 5, 11),
      note: null,
      version: 1,
      deletedAt: null,
      updatedAt: now,
    );

    await repo.markAchieved(achievement);

    final syncRows = await db.query(
      'sync_state',
      where: 'record_id = ? AND table_name = ?',
      whereArgs: ['ach-2', 'milestone_achievement'],
    );
    expect(syncRows.length, 1);
    expect(syncRows.first['dirty'], 1);
    expect(syncRows.first['version'], 1);
    expect(syncRows.first['updated_at'], isNotNull);
  });

  test('markAchieved() auto-generates UUID when id is empty', () async {
    final now = DateTime.utc(2026, 5, 13, 9);
    final achievement = MilestoneAchievement(
      id: '',
      babyId: 'b1',
      milestoneId: 'ms-walk',
      achievedOn: DateTime.utc(2026, 5, 12),
      note: null,
      version: 1,
      deletedAt: null,
      updatedAt: now,
    );

    await repo.markAchieved(achievement);

    final rows = await db.query('milestone_achievement');
    expect(rows.length, 1);
    final insertedId = rows.first['id'] as String;
    expect(insertedId, isNotEmpty,
        reason: 'repository should generate a non-empty UUID when id is empty');
  });

  // ---------------------------------------------------------------------------
  // allForBaby()
  // ---------------------------------------------------------------------------

  test('allForBaby() returns only non-deleted rows ordered by achieved_on ASC',
      () async {
    final now = DateTime.utc(2026, 5, 13, 9);

    // First achievement (later date)
    final ach1 = MilestoneAchievement(
      id: 'ach-a',
      babyId: 'b1',
      milestoneId: 'ms-smile',
      achievedOn: DateTime.utc(2026, 5, 5),
      version: 1,
      updatedAt: now,
    );
    // Second achievement (earlier date — should come first in ASC order)
    final ach2 = MilestoneAchievement(
      id: 'ach-b',
      babyId: 'b1',
      milestoneId: 'ms-crawl',
      achievedOn: DateTime.utc(2026, 5, 3),
      version: 1,
      updatedAt: now,
    );
    // Third achievement — will be unmarked
    final ach3 = MilestoneAchievement(
      id: 'ach-c',
      babyId: 'b1',
      milestoneId: 'ms-walk',
      achievedOn: DateTime.utc(2026, 5, 1),
      version: 1,
      updatedAt: now,
    );

    await repo.markAchieved(ach1);
    await repo.markAchieved(ach2);
    await repo.markAchieved(ach3);
    await repo.unmark('ach-c');

    final results = await repo.allForBaby('b1');
    expect(results.length, 2,
        reason: 'soft-deleted row must be excluded');
    // ASC by achieved_on: ach2 (May 3) then ach1 (May 5)
    expect(results[0].id, 'ach-b');
    expect(results[1].id, 'ach-a');
  });

  test('allForBaby() excludes soft-deleted achievements', () async {
    final now = DateTime.utc(2026, 5, 13, 9);
    final achievement = MilestoneAchievement(
      id: 'ach-only',
      babyId: 'b1',
      milestoneId: 'ms-smile',
      achievedOn: DateTime.utc(2026, 5, 10),
      version: 1,
      updatedAt: now,
    );

    await repo.markAchieved(achievement);
    await repo.unmark('ach-only');

    final results = await repo.allForBaby('b1');
    expect(results, isEmpty,
        reason: 'unmarked achievement must not appear in allForBaby');
  });

  // ---------------------------------------------------------------------------
  // unmark()
  // ---------------------------------------------------------------------------

  test('unmark() sets deleted_at, bumps version to 2, marks sync_state dirty=1',
      () async {
    final now = DateTime.utc(2026, 5, 13, 9);
    final achievement = MilestoneAchievement(
      id: 'ach-unmark',
      babyId: 'b1',
      milestoneId: 'ms-smile',
      achievedOn: DateTime.utc(2026, 5, 10),
      version: 1,
      updatedAt: now,
    );

    await repo.markAchieved(achievement);

    // Flip sync dirty=0 to confirm unmark sets it back to 1.
    await db.update(
      'sync_state',
      {'dirty': 0},
      where: 'record_id = ? AND table_name = ?',
      whereArgs: ['ach-unmark', 'milestone_achievement'],
    );

    await repo.unmark('ach-unmark');

    // Verify milestone_achievement row.
    final rows = await db.query(
      'milestone_achievement',
      where: 'id = ?',
      whereArgs: ['ach-unmark'],
    );
    expect(rows.length, 1);
    expect(rows.first['deleted_at'], isNotNull,
        reason: 'deleted_at must be set after unmark');
    expect(rows.first['version'], 2,
        reason: 'version must increment from 1 to 2');

    // Verify sync_state row.
    final syncRows = await db.query(
      'sync_state',
      where: 'record_id = ? AND table_name = ?',
      whereArgs: ['ach-unmark', 'milestone_achievement'],
    );
    expect(syncRows.length, 1);
    expect(syncRows.first['dirty'], 1,
        reason: 'sync_state must be dirty after unmark');
    expect(syncRows.first['version'], 2,
        reason: 'sync_state version must match the bumped achievement version');
  });

  test('unmark() on non-existent id is a no-op', () async {
    // No rows exist — this must not throw.
    await expectLater(
      repo.unmark('non-existent-uuid-1234'),
      completes,
    );

    // DB should still be empty.
    final rows = await db.query('milestone_achievement');
    expect(rows, isEmpty);
    final syncRows = await db.query(
      'sync_state',
      where: 'table_name = ?',
      whereArgs: ['milestone_achievement'],
    );
    expect(syncRows, isEmpty);
  });
}
