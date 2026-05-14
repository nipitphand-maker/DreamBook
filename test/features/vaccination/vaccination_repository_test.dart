import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/db/migrations/m001_initial.dart';
import 'package:dreambook/core/db/migrations/m002_v2.dart';
import 'package:dreambook/core/db/migrations/m003_v3.dart';
import 'package:dreambook/core/db/migrations/migrations.dart';
import 'package:dreambook/features/vaccination/data/vaccination_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  late Database db;
  late ProviderContainer container;
  late VaccinationRepository repo;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (d, _) async {
          await Migrations([m001Initial, m002V2, m003V3]).runAll(d);
        },
      ),
    );
    await db.execute('PRAGMA foreign_keys = ON');
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((_) async => db),
      ],
    );
    repo = container.read(vaccinationRepositoryProvider);
    // Insert a baby for FK satisfaction.
    await db.insert('baby', {
      'id': 'b1',
      'name': 'Mali',
      'dob': '2026-03-01',
      'preferred_unit': 'oz',
      'created_at': '2026-05-14T00:00:00.000Z',
      'updated_at': '2026-05-14T00:00:00.000Z',
      'version': 1,
    });
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('listFor() returns empty when no vaccinations', () async {
    final list = await repo.listFor('b1');
    expect(list, isEmpty);
  });

  test('listFor() excludes soft-deleted records', () async {
    final keeper = await repo.insert(
      babyId: 'b1',
      vaccineName: 'Hepatitis B (Hep B)',
      givenOn: DateTime.utc(2026, 5, 10),
    );
    final goner = await repo.insert(
      babyId: 'b1',
      vaccineName: 'DTaP',
      givenOn: DateTime.utc(2026, 5, 12),
    );

    await repo.softDelete(goner.id, babyId: 'b1');

    final list = await repo.listFor('b1');
    expect(list.length, 1);
    expect(list.first.id, keeper.id);
  });

  test('listFor() orders by given_on DESC', () async {
    final oldShot = await repo.insert(
      babyId: 'b1',
      vaccineName: 'Hepatitis B (Hep B)',
      givenOn: DateTime.utc(2026, 3, 1),
    );
    final newShot = await repo.insert(
      babyId: 'b1',
      vaccineName: 'DTaP',
      givenOn: DateTime.utc(2026, 5, 1),
    );
    final midShot = await repo.insert(
      babyId: 'b1',
      vaccineName: 'MMR',
      givenOn: DateTime.utc(2026, 4, 1),
    );

    final list = await repo.listFor('b1');
    expect(list.map((r) => r.id).toList(), [
      newShot.id,
      midShot.id,
      oldShot.id,
    ]);
  });

  test('insert() persists vaccination row with correct fields', () async {
    final givenOn = DateTime.utc(2026, 5, 14, 10);
    final record = await repo.insert(
      babyId: 'b1',
      vaccineName: 'Hepatitis B (Hep B)',
      givenOn: givenOn,
      clinic: 'St. Louis Pediatrics',
      note: 'no reaction',
    );

    expect(record.babyId, 'b1');
    expect(record.vaccineName, 'Hepatitis B (Hep B)');
    expect(record.givenOn, givenOn);
    expect(record.clinic, 'St. Louis Pediatrics');
    expect(record.note, 'no reaction');
    expect(record.version, 1);
    expect(record.deletedAt, isNull);

    // v4 UUID check.
    final uuidV4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    expect(uuidV4.hasMatch(record.id), isTrue,
        reason: 'id should be a v4 UUID, got "${record.id}"');

    final rows = await db.query('vaccination');
    expect(rows.length, 1);
    expect(rows.first['id'], record.id);
    expect(rows.first['baby_id'], 'b1');
    expect(rows.first['vaccine_name'], 'Hepatitis B (Hep B)');
    expect(rows.first['given_on'], givenOn.toIso8601String());
    expect(rows.first['clinic'], 'St. Louis Pediatrics');
    expect(rows.first['note'], 'no reaction');
    expect(rows.first['version'], 1);
    expect(rows.first['deleted_at'], isNull);
  });

  test('insert() writes sync_state row with dirty=1 and version=1', () async {
    final record = await repo.insert(
      babyId: 'b1',
      vaccineName: 'DTaP',
      givenOn: DateTime.utc(2026, 5, 14),
    );

    final rows = await db.query(
      'sync_state',
      where: 'record_id = ? AND table_name = ?',
      whereArgs: [record.id, 'vaccination'],
    );
    expect(rows.length, 1);
    expect(rows.first['dirty'], 1);
    expect(rows.first['version'], 1);
    expect(rows.first['updated_at'], isNotNull);
  });

  test('softDelete() sets deleted_at and bumps version', () async {
    final record = await repo.insert(
      babyId: 'b1',
      vaccineName: 'MMR',
      givenOn: DateTime.utc(2026, 5, 14),
    );
    expect(record.version, 1);

    await repo.softDelete(record.id, babyId: 'b1');

    final rows = await db.query(
      'vaccination',
      where: 'id = ?',
      whereArgs: [record.id],
    );
    expect(rows.length, 1);
    expect(rows.first['deleted_at'], isNotNull);
    expect(rows.first['version'], 2);
  });

  test('softDelete() writes sync_state dirty=1 with bumped version',
      () async {
    final record = await repo.insert(
      babyId: 'b1',
      vaccineName: 'MMR',
      givenOn: DateTime.utc(2026, 5, 14),
    );

    // Flip dirty=0 to verify softDelete flips it back to 1.
    await db.update(
      'sync_state',
      {'dirty': 0},
      where: 'record_id = ? AND table_name = ?',
      whereArgs: [record.id, 'vaccination'],
    );

    await repo.softDelete(record.id, babyId: 'b1');

    final sync = await db.query(
      'sync_state',
      where: 'record_id = ? AND table_name = ?',
      whereArgs: [record.id, 'vaccination'],
    );
    expect(sync.length, 1);
    expect(sync.first['dirty'], 1);
    expect(sync.first['version'], 2);
  });

  test('softDelete() is a no-op for unknown id', () async {
    // Should not throw and should not insert sync_state row.
    await repo.softDelete('does-not-exist', babyId: 'b1');

    final sync = await db.query(
      'sync_state',
      where: 'record_id = ?',
      whereArgs: ['does-not-exist'],
    );
    expect(sync, isEmpty);
  });
}
