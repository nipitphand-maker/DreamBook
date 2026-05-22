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
import 'package:dreambook/core/db/migrations/m011_medication_created_at.dart';
import 'package:dreambook/core/db/migrations/migrations.dart';
import 'package:dreambook/core/models/medication_dose.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/features/medication/data/medication_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  late Database db;
  late ProviderContainer container;
  late MedicationRepository repo;

  // Date fixtures — UTC throughout.
  final day = DateTime.utc(2026, 5, 13); // midnight
  final morning = day.add(const Duration(hours: 8));
  final evening = day.add(const Duration(hours: 20));
  final yesterday = day.subtract(const Duration(days: 1));

  MedicationDose dose({
    required String id,
    required DateTime givenAt,
    String drug = 'Paracetamol',
  }) {
    final now = DateTime.now().toUtc();
    return MedicationDose(
      id: id,
      babyId: 'b1',
      drugName: drug,
      doseAmount: 5.0,
      doseUnit: 'ml',
      givenAt: givenAt,
      version: 1,
      updatedAt: now,
      createdAt: now,
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({}); // no family.id → controller is no-op
    final prefs = await SharedPreferences.getInstance();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 11,
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
            m011MedicationCreatedAt,
          ]).runAll(d);
        },
      ),
    );
    await db.execute('PRAGMA foreign_keys = ON');
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWith((_) async => db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    repo = container.read(medicationRepositoryProvider);
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
  // insert()
  // ---------------------------------------------------------------------------

  test('insert() persists row with all required fields', () async {
    final d = dose(id: 'd1', givenAt: morning);
    await repo.insert(d);

    final rows = await db.query(
      'medication_dose',
      where: 'id = ?',
      whereArgs: ['d1'],
    );
    expect(rows.length, 1);
    final row = rows.first;
    expect(row['baby_id'], 'b1');
    expect(row['drug_name'], 'Paracetamol');
    expect(row['dose_amount'], 5.0);
    expect(row['dose_unit'], 'ml');
    expect(row['given_at'], morning.toIso8601String());
    expect(row['version'], 1);
    expect(row['deleted_at'], isNull);
  });

  test('insert() writes sync_state row with dirty=1 and version=1', () async {
    final d = dose(id: 'd2', givenAt: morning);
    await repo.insert(d);

    final rows = await db.query(
      'sync_state',
      where: 'record_id = ? AND table_name = ?',
      whereArgs: ['d2', 'medication_dose'],
    );
    expect(rows.length, 1);
    expect(rows.first['dirty'], 1);
    expect(rows.first['version'], 1);
    expect(rows.first['updated_at'], isNotNull);
  });

  test('insert() stores optional fields (nextDoseAt, note) when provided',
      () async {
    final nextDose = day.add(const Duration(hours: 14));
    final d = MedicationDose(
      id: 'd3',
      babyId: 'b1',
      drugName: 'Ibuprofen',
      doseAmount: 2.5,
      doseUnit: 'ml',
      givenAt: morning,
      nextDoseAt: nextDose,
      note: 'After meal',
      version: 1,
      updatedAt: DateTime.now().toUtc(),
      createdAt: DateTime.now().toUtc(),
    );
    await repo.insert(d);

    final rows = await db.query(
      'medication_dose',
      where: 'id = ?',
      whereArgs: ['d3'],
    );
    expect(rows.length, 1);
    final row = rows.first;
    expect(row['next_dose_at'], nextDose.toIso8601String());
    expect(row['note'], 'After meal');
    expect(row['drug_name'], 'Ibuprofen');
    expect(row['dose_amount'], 2.5);
    expect(row['dose_unit'], 'ml');
  });

  // ---------------------------------------------------------------------------
  // softDelete()
  // ---------------------------------------------------------------------------

  test('softDelete() sets deleted_at, bumps version to 2, marks sync_state dirty=1',
      () async {
    final d = dose(id: 'd4', givenAt: morning);
    await repo.insert(d);

    // Reset dirty to 0 to confirm softDelete re-sets it.
    await db.update(
      'sync_state',
      {'dirty': 0},
      where: 'record_id = ? AND table_name = ?',
      whereArgs: ['d4', 'medication_dose'],
    );

    await repo.softDelete('d4');

    final doseRows = await db.query(
      'medication_dose',
      where: 'id = ?',
      whereArgs: ['d4'],
    );
    expect(doseRows.length, 1);
    expect(doseRows.first['deleted_at'], isNotNull);
    expect(doseRows.first['version'], 2);

    final syncRows = await db.query(
      'sync_state',
      where: 'record_id = ? AND table_name = ?',
      whereArgs: ['d4', 'medication_dose'],
    );
    expect(syncRows.length, 1);
    expect(syncRows.first['dirty'], 1);
    expect(syncRows.first['version'], 2);
  });

  // ---------------------------------------------------------------------------
  // forBabyToday()
  // ---------------------------------------------------------------------------

  test(
      'forBabyToday() returns doses within today window (logicalDayStart to +24h), ordered DESC',
      () async {
    final morningDose = dose(id: 'td1', givenAt: morning);
    final eveningDose = dose(id: 'td2', givenAt: evening);
    final yesterdayDose = dose(id: 'td3', givenAt: yesterday);

    await repo.insert(morningDose);
    await repo.insert(eveningDose);
    await repo.insert(yesterdayDose);

    final results = await repo.forBabyToday('b1', day);

    // Only today's doses (morning + evening) — NOT yesterday.
    expect(results.length, 2);
    // DESC order: evening first, then morning.
    expect(results[0].id, 'td2');
    expect(results[1].id, 'td1');
  });

  test('forBabyToday() excludes soft-deleted doses', () async {
    final d = dose(id: 'td4', givenAt: morning);
    await repo.insert(d);
    await repo.softDelete('td4');

    final results = await repo.forBabyToday('b1', day);
    expect(results, isEmpty);
  });

  // ---------------------------------------------------------------------------
  // forBabyDateRange()
  // ---------------------------------------------------------------------------

  test('forBabyDateRange() returns doses within range, ordered ASC', () async {
    // Range: day to day+2 (exclusive upper bound).
    final from = day;
    final to = day.add(const Duration(days: 2));
    final twoDaysLater =
        day.add(const Duration(days: 2, hours: 6)); // outside range

    final d1 = dose(id: 'dr1', givenAt: morning); // inside range
    final d2 = dose(id: 'dr2', givenAt: evening); // inside range
    final d3 = dose(id: 'dr3', givenAt: twoDaysLater); // outside range

    await repo.insert(d1);
    await repo.insert(d2);
    await repo.insert(d3);

    final results = await repo.forBabyDateRange('b1', from, to);

    expect(results.length, 2);
    // ASC order: morning first, then evening.
    expect(results[0].id, 'dr1');
    expect(results[1].id, 'dr2');
  });

  test('forBabyDateRange() excludes soft-deleted doses', () async {
    final d = dose(id: 'dr4', givenAt: morning);
    await repo.insert(d);
    await repo.softDelete('dr4');

    final results = await repo.forBabyDateRange(
      'b1',
      day,
      day.add(const Duration(days: 1)),
    );
    expect(results, isEmpty);
  });

  // ---------------------------------------------------------------------------
  // lastDoseForBaby()
  // ---------------------------------------------------------------------------

  test('lastDoseForBaby() returns the most recent dose by given_at', () async {
    final noon = day.add(const Duration(hours: 12));

    final d1 = dose(id: 'ld1', givenAt: morning);
    final d2 = dose(id: 'ld2', givenAt: noon);
    final d3 = dose(id: 'ld3', givenAt: evening);

    await repo.insert(d1);
    await repo.insert(d2);
    await repo.insert(d3);

    final last = await repo.lastDoseForBaby('b1');
    expect(last, isNotNull);
    expect(last!.id, 'ld3'); // evening is the latest
  });

  test('lastDoseForBaby() returns null when no non-deleted doses exist',
      () async {
    final d = dose(id: 'ld4', givenAt: morning);
    await repo.insert(d);
    await repo.softDelete('ld4');

    final last = await repo.lastDoseForBaby('b1');
    expect(last, isNull);
  });
}
