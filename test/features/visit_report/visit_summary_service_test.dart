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
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/features/visit_report/data/visit_summary_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  late Database db;
  late ProviderContainer container;
  late VisitSummaryService service;

  // Tests freeze "today" by reasoning relative to DateTime.now()'s midnight
  // UTC. The service computes its window from DateTime.now().toUtc(), so we
  // anchor inserted rows around that same anchor.
  late DateTime todayMidnightUtc;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 11,
        onCreate: (d, _) async {
          await Migrations([
            m001Initial, m002V2, m003V3, m004V4, m005DailyNote,
            m006SyncWrittenBy, m007SyncCursors, m008Milestone,
            m009TempReading, m010Medication, m011MedicationCreatedAt,
          ]).runAll(d);
        },
      ),
    );
    await db.execute('PRAGMA foreign_keys = ON');

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((_) async => db),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    service = container.read(visitSummaryServiceProvider);

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

    // Service buckets by LOCAL calendar day (DateTime.now() local time).
    // Use local midnight (kept as a non-UTC DateTime — the variable name is
    // historical) so fixtures align with the service's bucket boundaries
    // regardless of the runner's timezone or wall-clock hour.
    final nowLocal = DateTime.now();
    todayMidnightUtc =
        DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> insertFeed({
    required String id,
    required DateTime startedAt,
    double? oz,
    String type = 'bottle',
  }) async {
    await db.insert('feed', {
      'id': id,
      'baby_id': 'b1',
      'type': type,
      'oz': oz,
      'started_at': startedAt.toIso8601String(),
      'created_at': startedAt.toIso8601String(),
      'updated_at': startedAt.toIso8601String(),
      'version': 1,
    });
  }

  Future<void> insertDiaper({
    required String id,
    required DateTime occurredAt,
    required String type,
  }) async {
    await db.insert('diaper', {
      'id': id,
      'baby_id': 'b1',
      'type': type,
      'occurred_at': occurredAt.toIso8601String(),
      'created_at': occurredAt.toIso8601String(),
      'updated_at': occurredAt.toIso8601String(),
      'version': 1,
    });
  }

  Future<void> insertTempReading({
    required String id,
    required DateTime takenAt,
    required double celsius,
  }) async {
    await db.insert('temp_reading', {
      'id': id,
      'baby_id': 'b1',
      'celsius': celsius,
      'taken_at': takenAt.toIso8601String(),
      'version': 1,
      'updated_at': takenAt.toIso8601String(),
    });
  }

  Future<void> insertMedication({
    required String id,
    required DateTime givenAt,
    String drugName = 'Paracetamol',
    double doseAmount = 5.0,
    String doseUnit = 'ml',
  }) async {
    await db.insert('medication_dose', {
      'id': id,
      'baby_id': 'b1',
      'drug_name': drugName,
      'dose_amount': doseAmount,
      'dose_unit': doseUnit,
      'given_at': givenAt.toIso8601String(),
      'version': 1,
      'created_at': givenAt.toIso8601String(),
      'updated_at': givenAt.toIso8601String(),
    });
  }

  test('buildSummary returns empty days with zero totals when no data in range',
      () async {
    final data = await service.buildSummary(
        babyId: 'b1',
        rangeStart: todayMidnightUtc.subtract(const Duration(days: 6)),
        rangeEnd: todayMidnightUtc,
      );

    expect(data.babyName, 'Mali');
    expect(data.days.length, 7);
    for (final d in data.days) {
      expect(d.totalFeedOz, 0);
      expect(d.wetDiapers, 0);
      expect(d.soiledDiapers, 0);
      expect(d.totalSleepMin, 0);
      expect(d.longestSleepStretchMin, 0);
    }
    expect(data.vaccinations, isEmpty);
  });

  test('buildSummary aggregates feed oz correctly for a day within range',
      () async {
    // Two feeds today: 4.0 oz + 3.5 oz = 7.5 oz.
    final earlyToday = todayMidnightUtc.add(const Duration(hours: 8));
    final laterToday = todayMidnightUtc.add(const Duration(hours: 14));

    await insertFeed(id: 'f1', startedAt: earlyToday, oz: 4.0);
    await insertFeed(id: 'f2', startedAt: laterToday, oz: 3.5);

    final data = await service.buildSummary(
        babyId: 'b1',
        rangeStart: todayMidnightUtc.subtract(const Duration(days: 6)),
        rangeEnd: todayMidnightUtc,
      );

    // The last day in the window is today.
    final today = data.days.last;
    expect(today.totalFeedOz, closeTo(7.5, 1e-9));

    // Other days have no feeds.
    for (var i = 0; i < data.days.length - 1; i++) {
      expect(data.days[i].totalFeedOz, 0);
    }
  });

  test(
    'buildSummary counts wet and soiled diapers independently '
    '(pee=wet, poop=soiled, mixed=both)',
    () async {
      final t = todayMidnightUtc.add(const Duration(hours: 9));

      // 1 pee  → wet=1
      // 1 poop → soiled=1
      // 1 mixed → wet+=1, soiled+=1
      // 1 dry  → ignored
      await insertDiaper(id: 'd1', occurredAt: t, type: 'pee');
      await insertDiaper(
          id: 'd2', occurredAt: t.add(const Duration(minutes: 5)), type: 'poop');
      await insertDiaper(
          id: 'd3', occurredAt: t.add(const Duration(minutes: 10)), type: 'mixed');
      await insertDiaper(
          id: 'd4', occurredAt: t.add(const Duration(minutes: 15)), type: 'dry');

      final data = await service.buildSummary(
        babyId: 'b1',
        rangeStart: todayMidnightUtc.subtract(const Duration(days: 6)),
        rangeEnd: todayMidnightUtc,
      );
      final today = data.days.last;

      expect(today.wetDiapers, 2, reason: '1 pee + 1 mixed');
      expect(today.soiledDiapers, 2, reason: '1 poop + 1 mixed');
    },
  );

  test('buildSummary excludes entries outside the date range', () async {
    // rangeDays = 7 → window covers the last 7 calendar days (today + 6 prior).
    // An entry 10 days ago must NOT show up in any day bucket.
    final farPast = todayMidnightUtc
        .subtract(const Duration(days: 10))
        .add(const Duration(hours: 10));
    final today = todayMidnightUtc.add(const Duration(hours: 9));

    await insertFeed(id: 'old', startedAt: farPast, oz: 9.9);
    await insertFeed(id: 'now', startedAt: today, oz: 1.0);

    await insertDiaper(id: 'old-d', occurredAt: farPast, type: 'pee');
    await insertDiaper(id: 'now-d', occurredAt: today, type: 'pee');

    final data = await service.buildSummary(
        babyId: 'b1',
        rangeStart: todayMidnightUtc.subtract(const Duration(days: 6)),
        rangeEnd: todayMidnightUtc,
      );

    // Sum across all days must equal only the in-range entries.
    final totalOz = data.days.fold<double>(0, (a, d) => a + d.totalFeedOz);
    expect(totalOz, closeTo(1.0, 1e-9));

    final totalWet = data.days.fold<int>(0, (a, d) => a + d.wetDiapers);
    expect(totalWet, 1);
  });

  test(
    'buildSummary populates temperatures for the correct day',
    () async {
      final earlyToday = todayMidnightUtc.add(const Duration(hours: 8));
      final laterToday = todayMidnightUtc.add(const Duration(hours: 14));

      await insertTempReading(id: 't1', takenAt: earlyToday, celsius: 37.5);
      await insertTempReading(id: 't2', takenAt: laterToday, celsius: 38.2);

      final data = await service.buildSummary(
        babyId: 'b1',
        rangeStart: todayMidnightUtc.subtract(const Duration(days: 6)),
        rangeEnd: todayMidnightUtc,
      );
      final today = data.days.last;

      expect(today.temperatures.length, 2);
      expect(today.temperatures.map((t) => t.id).toSet(), {'t1', 't2'});

      // Other days must have empty temperatures.
      for (var i = 0; i < data.days.length - 1; i++) {
        expect(data.days[i].temperatures, isEmpty);
      }
    },
  );

  test(
    'buildSummary populates medications for the correct day',
    () async {
      final t = todayMidnightUtc.add(const Duration(hours: 9));

      await insertMedication(id: 'm1', givenAt: t, drugName: 'Paracetamol');
      await insertMedication(
        id: 'm2',
        givenAt: t.add(const Duration(hours: 4)),
        drugName: 'Ibuprofen',
      );

      final data = await service.buildSummary(
        babyId: 'b1',
        rangeStart: todayMidnightUtc.subtract(const Duration(days: 6)),
        rangeEnd: todayMidnightUtc,
      );
      final today = data.days.last;

      expect(today.medications.length, 2);
      expect(today.medications.map((m) => m.id).toSet(), {'m1', 'm2'});

      for (var i = 0; i < data.days.length - 1; i++) {
        expect(data.days[i].medications, isEmpty);
      }
    },
  );

  test(
    'buildSummary excludes temperatures and medications outside the date range',
    () async {
      final farPast = todayMidnightUtc
          .subtract(const Duration(days: 10))
          .add(const Duration(hours: 10));
      final today = todayMidnightUtc.add(const Duration(hours: 9));

      await insertTempReading(id: 'old-t', takenAt: farPast, celsius: 39.0);
      await insertTempReading(id: 'new-t', takenAt: today, celsius: 37.5);

      await insertMedication(id: 'old-m', givenAt: farPast);
      await insertMedication(id: 'new-m', givenAt: today);

      final data = await service.buildSummary(
        babyId: 'b1',
        rangeStart: todayMidnightUtc.subtract(const Duration(days: 6)),
        rangeEnd: todayMidnightUtc,
      );

      final totalTemps =
          data.days.fold<int>(0, (a, d) => a + d.temperatures.length);
      expect(totalTemps, 1, reason: 'only the in-range temperature');

      final totalMeds =
          data.days.fold<int>(0, (a, d) => a + d.medications.length);
      expect(totalMeds, 1, reason: 'only the in-range medication');
    },
  );
}
