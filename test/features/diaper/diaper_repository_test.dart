import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/db/migrations/m001_initial.dart';
import 'package:dreambook/core/db/migrations/m002_v2.dart';
import 'package:dreambook/core/db/migrations/migrations.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/providers/device_id_provider.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/features/diaper/data/diaper_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  late Database db;
  late ProviderContainer container;
  late DiaperRepository repo;
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
    repo = container.read(diaperRepositoryProvider);
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

  // Test 1: todayFor returns empty when no diapers
  test('todayFor returns empty when no diapers', () async {
    final diapers = await repo.todayFor('b1');
    expect(diapers, isEmpty);
  });

  // Test 2: todayFor excludes deleted diapers
  test('todayFor excludes deleted diapers', () async {
    final diaper = await repo.insert(
      babyId: 'b1',
      type: DiaperType.pee,
    );
    await repo.softDelete(diaper.id, babyId: 'b1');

    final diapers = await repo.todayFor('b1');
    expect(diapers, isEmpty);
  });

  // Test 3: todayFor excludes diapers from yesterday
  test('todayFor excludes diapers from yesterday', () async {
    final yesterday = DateTime.now().toUtc().subtract(const Duration(days: 1));
    await repo.insert(
      babyId: 'b1',
      type: DiaperType.pee,
      occurredAt: yesterday,
    );

    final diapers = await repo.todayFor('b1');
    expect(diapers, isEmpty);
  });

  // Test 4: todayFor orders by occurred_at DESC
  test('todayFor orders by occurred_at DESC', () async {
    final now = DateTime.now().toUtc();
    final earlier = now.subtract(const Duration(hours: 3));
    final middle = now.subtract(const Duration(hours: 1));

    await repo.insert(babyId: 'b1', type: DiaperType.pee, occurredAt: earlier);
    await repo.insert(babyId: 'b1', type: DiaperType.poop, occurredAt: now);
    await repo.insert(babyId: 'b1', type: DiaperType.mixed, occurredAt: middle);

    final diapers = await repo.todayFor('b1');
    expect(diapers.length, 3);
    // DESC: now first, then middle, then earlier
    expect(diapers[0].occurredAt.isAfter(diapers[1].occurredAt), isTrue);
    expect(diapers[1].occurredAt.isAfter(diapers[2].occurredAt), isTrue);
  });

  // Test 5: insert saves correct type
  test('insert saves correct type', () async {
    final diaper = await repo.insert(
      babyId: 'b1',
      type: DiaperType.poop,
    );

    expect(diaper.type, DiaperType.poop);
    expect(diaper.babyId, 'b1');

    final rows = await db.query('diaper', where: 'id = ?', whereArgs: [diaper.id]);
    expect(rows.length, 1);
    expect(rows.first['type'], 'poop');
    expect(rows.first['baby_id'], 'b1');
  });

  // Test 6: insert writes sync_state dirty row
  test('insert writes sync_state dirty row', () async {
    final diaper = await repo.insert(
      babyId: 'b1',
      type: DiaperType.pee,
    );

    final syncRows = await db.query(
      'sync_state',
      where: 'record_id = ? AND table_name = ?',
      whereArgs: [diaper.id, 'diaper'],
    );
    expect(syncRows.length, 1);
    expect(syncRows.first['dirty'], 1);
    expect(syncRows.first['version'], 1);
  });

  // Test 7: insert defaults occurredAt to now (within 1 second)
  test('insert defaults occurredAt to now (within 1 second)', () async {
    final before = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
    final diaper = await repo.insert(
      babyId: 'b1',
      type: DiaperType.dry,
    );
    final after = DateTime.now().toUtc().add(const Duration(seconds: 1));

    expect(diaper.occurredAt.isAfter(before), isTrue);
    expect(diaper.occurredAt.isBefore(after), isTrue);
  });

  // Test 8: softDelete sets deleted_at and bumps version
  test('softDelete sets deleted_at and bumps version', () async {
    final diaper = await repo.insert(
      babyId: 'b1',
      type: DiaperType.mixed,
    );
    expect(diaper.version, 1);

    await repo.softDelete(diaper.id, babyId: 'b1');

    final rows = await db.query('diaper', where: 'id = ?', whereArgs: [diaper.id]);
    expect(rows.first['deleted_at'], isNotNull);
    expect(rows.first['version'], 2);
  });
}
