import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/db/migrations/m001_initial.dart';
import 'package:dreambook/core/db/migrations/m002_v2.dart';
import 'package:dreambook/core/db/migrations/migrations.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/providers/device_id_provider.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/features/sleep/data/sleep_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  late Database db;
  late ProviderContainer container;
  late SleepRepository repo;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
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
        sharedPreferencesProvider.overrideWithValue(prefs),
        deviceIdProvider.overrideWithValue('test-device-fp'),
      ],
    );
    repo = container.read(sleepRepositoryProvider);
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

  // Test 1: todayFor returns empty when no sessions
  test('todayFor returns empty when no sessions', () async {
    final sessions = await repo.todayFor('b1');
    expect(sessions, isEmpty);
  });

  // Test 2: todayFor excludes deleted sessions
  test('todayFor excludes deleted sessions', () async {
    final sleep = await repo.start(
      babyId: 'b1',
      startedAt: DateTime.now(),
    );
    await repo.softDelete(sleep.id, babyId: 'b1');

    final sessions = await repo.todayFor('b1');
    expect(sessions, isEmpty);
  });

  // Test 3: todayFor excludes sessions from yesterday
  test('todayFor excludes sessions from yesterday', () async {
    // Deterministic local times — running at 00:00–03:00 local with
    // `DateTime.now()` makes the day boundary cross the fixture timestamp.
    final fixedLocalNow = DateTime(2026, 5, 13, 14);
    final yesterday = DateTime(2026, 5, 12, 14);
    await repo.start(
      babyId: 'b1',
      startedAt: yesterday,
    );

    final sessions = await repo.todayFor('b1', now: fixedLocalNow);
    expect(sessions, isEmpty);
  });

  // Test 4: activeFor returns null when no ongoing session
  test('activeFor returns null when no ongoing session', () async {
    final active = await repo.activeFor('b1');
    expect(active, isNull);
  });

  // Test 5: activeFor returns the session with ended_at IS NULL
  test('activeFor returns session with ended_at IS NULL', () async {
    final sleep = await repo.start(
      babyId: 'b1',
      startedAt: DateTime.now(),
    );

    final active = await repo.activeFor('b1');
    expect(active, isNotNull);
    expect(active!.id, sleep.id);
    expect(active.endedAt, isNull);
  });

  // Test 6: start inserts session with null endedAt + writes sync_state dirty
  test('start inserts session with null endedAt and writes sync_state dirty',
      () async {
    final now = DateTime.now();
    final sleep = await repo.start(
      babyId: 'b1',
      startedAt: now,
      location: SleepLocation.crib,
    );

    expect(sleep.babyId, 'b1');
    expect(sleep.endedAt, isNull);
    expect(sleep.durationMin, isNull);
    expect(sleep.location, SleepLocation.crib);

    // Verify DB row
    final rows =
        await db.query('sleep', where: 'id = ?', whereArgs: [sleep.id]);
    expect(rows.length, 1);
    expect(rows.first['ended_at'], isNull);
    expect(rows.first['duration_min'], isNull);

    // Verify sync_state dirty
    final syncRows = await db.query(
      'sync_state',
      where: 'record_id = ? AND table_name = ?',
      whereArgs: [sleep.id, 'sleep'],
    );
    expect(syncRows.length, 1);
    expect(syncRows.first['dirty'], 1);
    expect(syncRows.first['version'], 1);
  });

  // Test 7: end sets ended_at and calculates duration_min correctly
  test('end sets ended_at and calculates duration_min correctly', () async {
    final startedAt = DateTime.now().toUtc();
    final sleep = await repo.start(
      babyId: 'b1',
      startedAt: startedAt,
    );

    final endedAt = startedAt.add(const Duration(minutes: 90));
    final ended = await repo.end(sleep.id, babyId: 'b1', endedAt: endedAt);

    expect(ended.endedAt, isNotNull);
    expect(ended.durationMin, 90);

    // Verify DB row
    final rows =
        await db.query('sleep', where: 'id = ?', whereArgs: [sleep.id]);
    expect(rows.first['ended_at'], isNotNull);
    expect(rows.first['duration_min'], 90);
  });

  // Test 8: softDelete sets deleted_at and bumps version
  test('softDelete sets deleted_at and bumps version', () async {
    final sleep = await repo.start(
      babyId: 'b1',
      startedAt: DateTime.now(),
    );
    expect(sleep.version, 1);

    await repo.softDelete(sleep.id, babyId: 'b1');

    final rows =
        await db.query('sleep', where: 'id = ?', whereArgs: [sleep.id]);
    expect(rows.first['deleted_at'], isNotNull);
    expect(rows.first['version'], 2);
  });
}
