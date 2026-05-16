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
import 'package:dreambook/core/models/temp_reading.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/features/temperature/data/temp_reading_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  late Database db;
  late ProviderContainer container;
  late TempReadingRepository repo;

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
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((_) async => db),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    repo = container.read(tempReadingRepositoryProvider);
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

  TempReading _makeReading({
    String? id,
    String babyId = 'b1',
    DateTime? takenAt,
    double celsius = 37.5,
  }) {
    return TempReading(
      id: id ?? TempReadingRepository.newId(),
      babyId: babyId,
      takenAt: takenAt ?? DateTime.utc(2026, 5, 13, 10),
      celsius: celsius,
      version: 1,
      updatedAt: DateTime.utc(2026, 5, 13, 10),
    );
  }

  // Test 1: insert() persists row with all required fields
  test('insert() persists row with all required fields', () async {
    final reading = _makeReading(celsius: 37.5);
    await repo.insert(reading);

    final rows = await db.query(
      'temp_reading',
      where: 'id = ?',
      whereArgs: [reading.id],
    );
    expect(rows.length, 1);
    expect(rows.first['baby_id'], 'b1');
    expect(rows.first['celsius'], 37.5);
    expect(rows.first['version'], 1);
    expect(rows.first['deleted_at'], isNull);
  });

  // Test 2: insert() writes sync_state row with dirty=1 and version=1
  test('insert() writes sync_state row with dirty=1 and version=1', () async {
    final reading = _makeReading();
    await repo.insert(reading);

    final syncRows = await db.query(
      'sync_state',
      where: 'record_id = ? AND table_name = ?',
      whereArgs: [reading.id, 'temp_reading'],
    );
    expect(syncRows.length, 1);
    expect(syncRows.first['dirty'], 1);
    expect(syncRows.first['version'], 1);
  });

  // Test 3: insert() generates a valid UUID for id
  test('insert() generates a valid UUID for id', () async {
    final id = TempReadingRepository.newId();
    final reading = _makeReading(id: id);
    await repo.insert(reading);

    // RFC 4122 v4 UUID: xxxxxxxx-xxxx-4xxx-[89ab]xxx-xxxxxxxxxxxx
    final uuidV4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    expect(
      uuidV4.hasMatch(id),
      isTrue,
      reason: 'id should be a v4 UUID, got "$id"',
    );
  });

  // Test 4: softDelete() sets deleted_at, bumps version to 2, marks sync_state dirty=1
  test(
      'softDelete() sets deleted_at, bumps version to 2, marks sync_state dirty=1',
      () async {
    final reading = _makeReading();
    await repo.insert(reading);

    // Reset dirty to 0 to confirm softDelete flips it back to 1.
    await db.update(
      'sync_state',
      {'dirty': 0},
      where: 'record_id = ? AND table_name = ?',
      whereArgs: [reading.id, 'temp_reading'],
    );

    await repo.softDelete(reading.id);

    final rows = await db.query(
      'temp_reading',
      where: 'id = ?',
      whereArgs: [reading.id],
    );
    expect(rows.length, 1);
    expect(rows.first['deleted_at'], isNotNull);
    expect(rows.first['version'], 2);

    final syncRows = await db.query(
      'sync_state',
      where: 'record_id = ? AND table_name = ?',
      whereArgs: [reading.id, 'temp_reading'],
    );
    expect(syncRows.length, 1);
    expect(syncRows.first['dirty'], 1);
    expect(syncRows.first['version'], 2);
  });

  // Test 5: forBaby() returns only non-deleted rows ordered by taken_at DESC
  test('forBaby() returns only non-deleted rows ordered by taken_at DESC',
      () async {
    final past = _makeReading(
      id: TempReadingRepository.newId(),
      takenAt: DateTime.utc(2026, 5, 13, 8),
      celsius: 36.8,
    );
    final present = _makeReading(
      id: TempReadingRepository.newId(),
      takenAt: DateTime.utc(2026, 5, 13, 12),
      celsius: 37.2,
    );
    final future = _makeReading(
      id: TempReadingRepository.newId(),
      takenAt: DateTime.utc(2026, 5, 13, 16),
      celsius: 37.9,
    );

    await repo.insert(past);
    await repo.insert(present);
    await repo.insert(future);

    // Soft-delete the "present" reading.
    await repo.softDelete(present.id);

    final results = await repo.forBaby('b1');
    expect(results.length, 2);
    // DESC order: future (16:00) then past (08:00).
    expect(results[0].id, future.id);
    expect(results[1].id, past.id);
  });

  // Test 6: forBaby() respects the limit parameter
  test('forBaby() respects the limit parameter', () async {
    for (var i = 0; i < 5; i++) {
      await repo.insert(
        _makeReading(
          id: TempReadingRepository.newId(),
          takenAt: DateTime.utc(2026, 5, 13, i),
        ),
      );
    }

    final results = await repo.forBaby('b1', limit: 2);
    expect(results.length, 2);
  });

  // Test 7: forBabyDateRange() returns only readings within the window
  test('forBabyDateRange() returns only readings within the window', () async {
    final inside = _makeReading(
      id: TempReadingRepository.newId(),
      takenAt: DateTime.utc(2026, 5, 13, 12),
      celsius: 37.5,
    );
    final outside = _makeReading(
      id: TempReadingRepository.newId(),
      takenAt: DateTime.utc(2026, 5, 14, 12),
      celsius: 38.0,
    );

    await repo.insert(inside);
    await repo.insert(outside);

    final results = await repo.forBabyDateRange(
      'b1',
      DateTime.utc(2026, 5, 13, 0),
      DateTime.utc(2026, 5, 14, 0),
    );

    expect(results.length, 1);
    expect(results.first.id, inside.id);
  });

  // Test 8: forBabyDateRange() excludes soft-deleted readings
  test('forBabyDateRange() excludes soft-deleted readings', () async {
    final reading = _makeReading(
      id: TempReadingRepository.newId(),
      takenAt: DateTime.utc(2026, 5, 13, 12),
    );
    await repo.insert(reading);
    await repo.softDelete(reading.id);

    final results = await repo.forBabyDateRange(
      'b1',
      DateTime.utc(2026, 5, 13, 0),
      DateTime.utc(2026, 5, 14, 0),
    );

    expect(results, isEmpty);
  });

  // Test 9: TempReading.fahrenheit getter converts correctly
  test('TempReading.fahrenheit getter converts correctly', () {
    final reading = TempReading(
      id: 'test-id',
      babyId: 'b1',
      takenAt: DateTime.utc(2026, 5, 13),
      celsius: 37.0,
      version: 1,
      updatedAt: DateTime.utc(2026, 5, 13),
    );

    expect(reading.fahrenheit, closeTo(98.6, 0.01));
  });
}
