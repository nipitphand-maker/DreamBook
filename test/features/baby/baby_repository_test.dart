import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/db/migrations/m001_initial.dart';
import 'package:dreambook/core/db/migrations/m002_v2.dart';
import 'package:dreambook/core/db/migrations/migrations.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/providers/device_id_provider.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/features/baby/data/baby_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  late Database db;
  late ProviderContainer container;
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
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  BabyRepository repo() => container.read(babyRepositoryProvider);

  test('insert() persists baby row with required fields', () async {
    final dob = DateTime.utc(2026, 3, 1);
    final baby = await repo().insert(
      name: 'Mali',
      nickname: 'Mali-bear',
      dob: dob,
      sex: BabySex.female,
      preferredUnit: PreferredUnit.oz,
    );

    expect(baby.name, 'Mali');
    expect(baby.nickname, 'Mali-bear');
    expect(baby.sex, BabySex.female);
    expect(baby.preferredUnit, PreferredUnit.oz);
    expect(baby.version, 1);
    expect(baby.deletedAt, isNull);

    final rows = await db.query('baby');
    expect(rows.length, 1);
    expect(rows.first['name'], 'Mali');
    expect(rows.first['nickname'], 'Mali-bear');
    expect(rows.first['sex'], 'female');
    expect(rows.first['preferred_unit'], 'oz');
    expect(rows.first['dob'], '2026-03-01');
    expect(rows.first['version'], 1);
    expect(rows.first['deleted_at'], isNull);
  });

  test('insert() generates v4 UUID for id', () async {
    final baby = await repo().insert(
      name: 'Mali',
      dob: DateTime.utc(2026, 3, 1),
    );

    // RFC 4122 v4 UUID: xxxxxxxx-xxxx-4xxx-[8-b]xxx-xxxxxxxxxxxx
    final uuidV4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    expect(uuidV4.hasMatch(baby.id), isTrue,
        reason: 'id should be a v4 UUID, got "${baby.id}"');
  });

  test('insert() writes sync_state row with dirty=1 and version=1', () async {
    final baby = await repo().insert(
      name: 'Mali',
      dob: DateTime.utc(2026, 3, 1),
    );

    final rows = await db.query(
      'sync_state',
      where: 'record_id = ? AND table_name = ?',
      whereArgs: [baby.id, 'baby'],
    );
    expect(rows.length, 1);
    expect(rows.first['dirty'], 1);
    expect(rows.first['version'], 1);
    expect(rows.first['updated_at'], isNotNull);
  });

  test('getActive() returns null when no babies exist', () async {
    final result = await repo().getActive();
    expect(result, isNull);
  });

  test(
      'getActive() returns the only baby when one exists (excludes soft-deleted)',
      () async {
    // Insert baby A (will be soft-deleted).
    final a = await repo().insert(
      name: 'Mali',
      dob: DateTime.utc(2026, 3, 1),
    );
    await repo().softDelete(a.id);

    // Insert baby B (active).
    final b = await repo().insert(
      name: 'Nara',
      dob: DateTime.utc(2026, 4, 1),
    );

    final active = await repo().getActive();
    expect(active, isNotNull);
    expect(active!.id, b.id);
    expect(active.name, 'Nara');
  });

  test('softDelete() sets deleted_at, bumps version, marks sync_state dirty',
      () async {
    final baby = await repo().insert(
      name: 'Mali',
      dob: DateTime.utc(2026, 3, 1),
    );

    // Mark sync_state clean to verify it's flipped back to dirty.
    await db.update(
      'sync_state',
      {'dirty': 0},
      where: 'record_id = ? AND table_name = ?',
      whereArgs: [baby.id, 'baby'],
    );

    await repo().softDelete(baby.id);

    final rows =
        await db.query('baby', where: 'id = ?', whereArgs: [baby.id]);
    expect(rows.length, 1);
    expect(rows.first['deleted_at'], isNotNull);
    expect(rows.first['version'], 2);

    final sync = await db.query(
      'sync_state',
      where: 'record_id = ? AND table_name = ?',
      whereArgs: [baby.id, 'baby'],
    );
    expect(sync.length, 1);
    expect(sync.first['dirty'], 1);
    expect(sync.first['version'], 2);
  });
}
