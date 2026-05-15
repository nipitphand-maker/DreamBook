import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/db/migrations/m001_initial.dart';
import 'package:dreambook/core/db/migrations/m002_v2.dart';
import 'package:dreambook/core/db/migrations/m003_v3.dart';
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
        version: 3,
        onCreate: (d, _) async {
          await Migrations([m001Initial, m002V2, m003V3]).runAll(d);
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

    final now = DateTime.now().toUtc();
    todayMidnightUtc = DateTime.utc(now.year, now.month, now.day);
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

  test('buildSummary returns empty days with zero totals when no data in range',
      () async {
    final data = await service.buildSummary(babyId: 'b1', rangeDays: 7);

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

    final data = await service.buildSummary(babyId: 'b1', rangeDays: 7);

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

      final data = await service.buildSummary(babyId: 'b1', rangeDays: 7);
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

    final data = await service.buildSummary(babyId: 'b1', rangeDays: 7);

    // Sum across all days must equal only the in-range entries.
    final totalOz = data.days.fold<double>(0, (a, d) => a + d.totalFeedOz);
    expect(totalOz, closeTo(1.0, 1e-9));

    final totalWet = data.days.fold<int>(0, (a, d) => a + d.wetDiapers);
    expect(totalWet, 1);
  });
}
