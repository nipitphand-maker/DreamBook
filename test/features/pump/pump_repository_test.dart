import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/db/migrations/m001_initial.dart';
import 'package:dreambook/core/db/migrations/m002_v2.dart';
import 'package:dreambook/core/db/migrations/migrations.dart';
import 'package:dreambook/features/pump/data/pump_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  late Database db;
  late ProviderContainer container;
  late PumpRepository repo;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (d, _) async {
          await Migrations([m001Initial, m002V2]).runAll(d);
        },
      ),
    );
    await db.execute('PRAGMA foreign_keys = ON');
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((_) async => db),
      ],
    );
    repo = container.read(pumpRepositoryProvider);
    // Insert a baby for FK satisfaction.
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

  // Test 1: insert() persists pump_session row with paused_duration_min default 0
  test('insert() persists pump_session row with paused_duration_min default 0',
      () async {
    final startedAt = DateTime.utc(2026, 5, 13, 10);
    final session = await repo.insert(
      babyId: 'b1',
      startedAt: startedAt,
      leftOz: 2.5,
      rightOz: 1.5,
    );

    expect(session.babyId, 'b1');
    expect(session.leftOz, 2.5);
    expect(session.rightOz, 1.5);
    expect(session.pausedDurationMin, 0);
    expect(session.version, 1);
    expect(session.deletedAt, isNull);

    final rows = await db.query('pump_session');
    expect(rows.length, 1);
    expect(rows.first['baby_id'], 'b1');
    expect(rows.first['left_oz'], 2.5);
    expect(rows.first['right_oz'], 1.5);
    expect(rows.first['paused_duration_min'], 0);
    expect(rows.first['version'], 1);
    expect(rows.first['deleted_at'], isNull);
  });

  // Test 2: insert() generates v4 UUID for id
  test('insert() generates v4 UUID for id', () async {
    final session = await repo.insert(
      babyId: 'b1',
      startedAt: DateTime.utc(2026, 5, 13, 10),
    );

    final uuidV4Regex = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    expect(uuidV4Regex.hasMatch(session.id), isTrue,
        reason: 'id "${session.id}" is not a valid UUID v4');
  });

  // Test 3: insert() writes sync_state row dirty=1 version=1 for pump_session
  test('insert() writes sync_state row dirty=1 version=1 for pump_session',
      () async {
    final session = await repo.insert(
      babyId: 'b1',
      startedAt: DateTime.utc(2026, 5, 13, 10),
    );

    final syncRows = await db.query(
      'sync_state',
      where: 'record_id = ? AND table_name = ?',
      whereArgs: [session.id, 'pump_session'],
    );
    expect(syncRows.length, 1);
    expect(syncRows.first['dirty'], 1);
    expect(syncRows.first['version'], 1);
  });

  // Test 4: insert() with 0 bottles creates only pump_session, no stash_bottle rows
  test('insert() with 0 bottles creates only pump_session, no stash_bottle rows',
      () async {
    await repo.insert(
      babyId: 'b1',
      startedAt: DateTime.utc(2026, 5, 13, 10),
      bottles: const [],
    );

    final stashRows = await db.query('stash_bottle');
    expect(stashRows, isEmpty);
  });

  // Test 5: insert() with 2 bottles atomically creates pump_session + 2 stash_bottles + 3 sync_state rows
  test(
      'insert() with 2 bottles atomically creates pump_session + 2 stash_bottles + 3 sync_state rows',
      () async {
    await repo.insert(
      babyId: 'b1',
      startedAt: DateTime.utc(2026, 5, 13, 10),
      bottles: const [
        PendingBottle(oz: 4.0),
        PendingBottle(oz: 2.5),
      ],
    );

    final stashRows = await db.query('stash_bottle');
    expect(stashRows.length, 2);

    final syncRows = await db.query('sync_state');
    expect(syncRows.length, 3);
  });

  // Test 6: insert() with bottles — each stash_bottle.pump_session_id links to new session
  test(
      'insert() with bottles — each stash_bottle.pump_session_id links to new session',
      () async {
    final session = await repo.insert(
      babyId: 'b1',
      startedAt: DateTime.utc(2026, 5, 13, 10),
      bottles: const [
        PendingBottle(oz: 4.0),
        PendingBottle(oz: 2.5),
      ],
    );

    final stashRows = await db.query('stash_bottle');
    expect(stashRows.length, 2);
    for (final row in stashRows) {
      expect(row['pump_session_id'], session.id);
    }
  });

  // Test 7: todayFor(babyId) returns rows for today sorted started_at DESC, excludes soft-deleted
  test(
      'todayFor(babyId) returns rows for today sorted started_at DESC, excludes soft-deleted',
      () async {
    final now = DateTime.utc(2026, 5, 13);
    final earlier = await repo.insert(
      babyId: 'b1',
      startedAt: DateTime.utc(2026, 5, 13, 8),
    );
    final later = await repo.insert(
      babyId: 'b1',
      startedAt: DateTime.utc(2026, 5, 13, 10),
    );

    // Soft-delete the earlier session
    await repo.softDelete(earlier.id, babyId: 'b1');

    final sessions = await repo.todayFor('b1', now: now);
    expect(sessions.length, 1);
    expect(sessions.first.id, later.id);
  });

  // Test 8: softDelete() pump_session does NOT delete companion stash_bottles
  test('softDelete() pump_session does NOT delete companion stash_bottles',
      () async {
    final session = await repo.insert(
      babyId: 'b1',
      startedAt: DateTime.utc(2026, 5, 13, 10),
      bottles: const [
        PendingBottle(oz: 4.0),
        PendingBottle(oz: 2.5),
      ],
    );

    await repo.softDelete(session.id, babyId: 'b1');

    // Stash bottles should still exist (milk physically still in freezer)
    final stashRows = await db.query('stash_bottle');
    expect(stashRows.length, 2);
  });
}
