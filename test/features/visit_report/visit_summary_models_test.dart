import 'package:dreambook/core/models/vaccination.dart';
import 'package:dreambook/features/visit_report/data/visit_summary_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DaySummary', () {
    test('constructs with all zeros (empty-day edge case)', () {
      final day = DaySummary(
        date: DateTime.utc(2025, 3, 15),
        totalFeedOz: 0,
        wetDiapers: 0,
        soiledDiapers: 0,
        totalSleepMin: 0,
        longestSleepStretchMin: 0,
      );

      expect(day.date, DateTime.utc(2025, 3, 15));
      expect(day.totalFeedOz, 0.0);
      expect(day.wetDiapers, 0);
      expect(day.soiledDiapers, 0);
      expect(day.totalSleepMin, 0);
      expect(day.longestSleepStretchMin, 0);
    });

    test('constructs with all fields set', () {
      final day = DaySummary(
        date: DateTime.utc(2025, 4, 1),
        totalFeedOz: 24.5,
        wetDiapers: 6,
        soiledDiapers: 3,
        totalSleepMin: 780,
        longestSleepStretchMin: 240,
      );

      expect(day.date, DateTime.utc(2025, 4, 1));
      expect(day.totalFeedOz, 24.5);
      expect(day.wetDiapers, 6);
      expect(day.soiledDiapers, 3);
      expect(day.totalSleepMin, 780);
      expect(day.longestSleepStretchMin, 240);
    });

    test('totalFeedOz preserves double precision', () {
      final day = DaySummary(
        date: DateTime.utc(2025, 4, 2),
        totalFeedOz: 3.14159265358979,
        wetDiapers: 0,
        soiledDiapers: 0,
        totalSleepMin: 0,
        longestSleepStretchMin: 0,
      );

      expect(day.totalFeedOz, closeTo(3.14159265358979, 1e-12));
    });

    test('mixed diapers count for both wetDiapers and soiledDiapers', () {
      // A "mixed" diaper (pee + poop) is reflected by the service as incrementing
      // BOTH wetDiapers and soiledDiapers on DaySummary. This test verifies
      // that DaySummary's two independent integer counters can represent this
      // overlap (i.e., wetDiapers and soiledDiapers can both be non-zero even
      // when the physical diaper count is smaller than their sum).
      final day = DaySummary(
        date: DateTime.utc(2025, 4, 3),
        totalFeedOz: 0,
        // 1 pee + 1 mixed → wetDiapers = 2
        wetDiapers: 2,
        // 1 poop + 1 mixed → soiledDiapers = 2
        soiledDiapers: 2,
        totalSleepMin: 0,
        longestSleepStretchMin: 0,
      );

      expect(day.wetDiapers, 2);
      expect(day.soiledDiapers, 2);
      // Combined count can exceed the number of distinct diaper events
      // because a single mixed diaper contributes to both buckets.
      expect(day.wetDiapers + day.soiledDiapers, greaterThan(2));
    });

    test('longestSleepStretchMin can equal totalSleepMin (single nap)', () {
      final day = DaySummary(
        date: DateTime.utc(2025, 4, 4),
        totalFeedOz: 0,
        wetDiapers: 0,
        soiledDiapers: 0,
        totalSleepMin: 180,
        longestSleepStretchMin: 180,
      );

      expect(day.longestSleepStretchMin, day.totalSleepMin);
    });
  });

  group('VisitSummaryData', () {
    final rangeStart = DateTime.utc(2025, 3, 9);
    final rangeEnd = DateTime.utc(2025, 3, 15, 23, 59, 59);

    test('constructs correctly with an empty days list', () {
      final data = VisitSummaryData(
        babyName: 'Nora',
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        days: const [],
        vaccinations: const [],
      );

      expect(data.babyName, 'Nora');
      expect(data.babyDob, isNull);
      expect(data.rangeStart, rangeStart);
      expect(data.rangeEnd, rangeEnd);
      expect(data.days, isEmpty);
      expect(data.vaccinations, isEmpty);
    });

    test('babyDob is null by default', () {
      final data = VisitSummaryData(
        babyName: 'Nora',
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        days: const [],
        vaccinations: const [],
      );

      expect(data.babyDob, isNull);
    });

    test('constructs correctly with babyDob provided', () {
      final dob = DateTime.utc(2025, 1, 1);
      final data = VisitSummaryData(
        babyName: 'Leo',
        babyDob: dob,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        days: const [],
        vaccinations: const [],
      );

      expect(data.babyDob, dob);
    });

    test('holds provided days list correctly', () {
      final days = [
        DaySummary(
          date: DateTime.utc(2025, 3, 14),
          totalFeedOz: 18.0,
          wetDiapers: 5,
          soiledDiapers: 2,
          totalSleepMin: 600,
          longestSleepStretchMin: 180,
        ),
        DaySummary(
          date: DateTime.utc(2025, 3, 15),
          totalFeedOz: 20.0,
          wetDiapers: 6,
          soiledDiapers: 3,
          totalSleepMin: 660,
          longestSleepStretchMin: 210,
        ),
      ];

      final data = VisitSummaryData(
        babyName: 'Mali',
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        days: days,
        vaccinations: const [],
      );

      expect(data.days.length, 2);
      expect(data.days.first.totalFeedOz, 18.0);
      expect(data.days.last.wetDiapers, 6);
    });

    test('holds provided vaccinations list correctly', () {
      final vax = [
        VaccinationRecord(
          id: 'v1',
          babyId: 'b1',
          vaccineName: 'Hep B',
          givenOn: DateTime.utc(2025, 3, 10),
          createdAt: DateTime.utc(2025, 3, 10, 9),
          updatedAt: DateTime.utc(2025, 3, 10, 9),
        ),
      ];

      final data = VisitSummaryData(
        babyName: 'Mali',
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        days: const [],
        vaccinations: vax,
      );

      expect(data.vaccinations.length, 1);
      expect(data.vaccinations.first.vaccineName, 'Hep B');
    });

    test('rangeStart and rangeEnd are stored as provided', () {
      final data = VisitSummaryData(
        babyName: 'Test',
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        days: const [],
        vaccinations: const [],
      );

      expect(data.rangeStart, rangeStart);
      expect(data.rangeEnd, rangeEnd);
    });
  });
}
