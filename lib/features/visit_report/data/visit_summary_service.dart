import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/features/baby/data/baby_repository.dart';
import 'package:dreambook/features/medication/data/medication_repository.dart';
import 'package:dreambook/features/temperature/data/temp_reading_repository.dart';
import 'package:dreambook/features/vaccination/data/vaccination_repository.dart';
import 'package:dreambook/features/visit_report/data/visit_summary_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Builds the data envelope for the Visit Report PDF.
///
/// Queries the encrypted local DB directly (the existing per-feature repos
/// only expose `todayFor()`, not date-range queries). Returns one
/// [DaySummary] per calendar day in the requested window, plus the full
/// vaccination list for the baby.
class VisitSummaryService {
  VisitSummaryService(this._ref);

  final Ref _ref;

  /// IMPORTANT — DESIGN NOTE:
  /// Visit Summary buckets events by LOCAL CALENDAR DAYS (00:00 to 23:59),
  /// NOT by the user's [dayStartHourProvider] preference. This is intentional:
  /// clinical PDF reports are read by doctors who expect calendar dates.
  ///
  /// Daily Summary (lib/features/summary/) DOES respect dayStartHour and
  /// uses [currentLogicalDayStart]. When dayStartHour != 0, the same event
  /// may appear in different day buckets between the two views. The 03:00
  /// feed appearing under "yesterday" in DailySummary but under "today" in
  /// the PDF is correct behavior, not a bug.
  Future<VisitSummaryData> buildSummary({
    required String babyId,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    final db = await _ref.read(appDatabaseProvider.future);

    final babies = await _ref.read(babyRepositoryProvider).list();
    final baby = babies.firstWhere(
      (b) => b.id == babyId,
      orElse: () => throw StateError('Baby not found'),
    );

    // Normalise to LOCAL midnight boundaries so events are bucketed by the
    // user's calendar day, not UTC day (e.g. Thai users at UTC+7).
    final rangeStartLocal = DateTime(
        rangeStart.year, rangeStart.month, rangeStart.day);
    // rangeEnd is inclusive: advance to start-of-next-day for DB WHERE clause.
    final rangeEndLocal = DateTime(
        rangeEnd.year, rangeEnd.month, rangeEnd.day)
        .add(const Duration(days: 1));

    // UTC strings for the DB WHERE clause
    final rangeStartUtc = rangeStartLocal.toUtc().toIso8601String();
    final rangeEndUtc = rangeEndLocal.toUtc().toIso8601String();

    final rangeDays = rangeEndLocal.difference(rangeStartLocal).inDays;

    final feedRows = await db.query(
      'feed',
      where:
          'baby_id = ? AND deleted_at IS NULL AND started_at >= ? AND started_at < ?',
      whereArgs: [
        babyId,
        rangeStartUtc,
        rangeEndUtc,
      ],
    );
    final feeds = feedRows.map(Feed.fromRow).toList();

    final diaperRows = await db.query(
      'diaper',
      where:
          'baby_id = ? AND deleted_at IS NULL AND occurred_at >= ? AND occurred_at < ?',
      whereArgs: [
        babyId,
        rangeStartUtc,
        rangeEndUtc,
      ],
    );
    final diapers = diaperRows.map(Diaper.fromRow).toList();

    final sleepRows = await db.query(
      'sleep',
      where:
          'baby_id = ? AND deleted_at IS NULL AND started_at >= ? AND started_at < ?',
      whereArgs: [
        babyId,
        rangeStartUtc,
        rangeEndUtc,
      ],
    );
    final sleeps = sleepRows.map(Sleep.fromRow).toList();

    final vaccinations =
        await _ref.read(vaccinationRepositoryProvider).listFor(babyId);

    final allTemps = await _ref
        .read(tempReadingRepositoryProvider)
        .forBabyDateRange(babyId, rangeStartLocal, rangeEndLocal);

    final allMedications = await _ref
        .read(medicationRepositoryProvider)
        .forBabyDateRange(babyId, rangeStartLocal.toUtc(), rangeEndLocal.toUtc());

    final days = <DaySummary>[];
    for (var i = 0; i < rangeDays; i++) {
      final dayStart = rangeStartLocal.add(Duration(days: i));
      final dayEnd = dayStart.add(const Duration(days: 1));

      final dayMedications = allMedications
          .where((m) =>
              !m.givenAt.isBefore(dayStart) && m.givenAt.isBefore(dayEnd))
          .toList();

      final dayFeeds = feeds
          .where((f) =>
              !f.startedAt.isBefore(dayStart) && f.startedAt.isBefore(dayEnd))
          .toList();
      final dayTemps = allTemps
          .where((t) =>
              !t.takenAt.isBefore(dayStart) && t.takenAt.isBefore(dayEnd))
          .toList();
      final dayDiapers = diapers
          .where((d) =>
              !d.occurredAt.isBefore(dayStart) &&
              d.occurredAt.isBefore(dayEnd))
          .toList();
      final daySleeps = sleeps
          .where((s) =>
              !s.startedAt.isBefore(dayStart) &&
              s.startedAt.isBefore(dayEnd) &&
              s.durationMin != null)
          .toList();

      final totalFeedOz =
          dayFeeds.fold<double>(0, (acc, f) => acc + (f.oz ?? 0));
      final wetDiapers = dayDiapers
          .where((d) => d.type == DiaperType.pee || d.type == DiaperType.mixed)
          .length;
      final soiledDiapers = dayDiapers
          .where(
              (d) => d.type == DiaperType.poop || d.type == DiaperType.mixed)
          .length;
      final totalSleepMin =
          daySleeps.fold<int>(0, (acc, s) => acc + (s.durationMin ?? 0));
      final longestStretch = daySleeps.isEmpty
          ? 0
          : daySleeps
              .map((s) => s.durationMin ?? 0)
              .reduce((a, b) => a > b ? a : b);

      days.add(DaySummary(
        date: dayStart,
        totalFeedOz: totalFeedOz,
        wetDiapers: wetDiapers,
        soiledDiapers: soiledDiapers,
        totalSleepMin: totalSleepMin,
        longestSleepStretchMin: longestStretch,
        temperatures: dayTemps,
        medications: dayMedications,
      ));
    }

    final rangeEndDisplay = DateTime(
        rangeEnd.year, rangeEnd.month, rangeEnd.day, 23, 59, 59);

    return VisitSummaryData(
      babyName: baby.nickname?.isNotEmpty == true ? baby.nickname! : baby.name,
      babyDob: baby.dob,
      rangeStart: rangeStartLocal,
      rangeEnd: rangeEndDisplay,
      days: days,
      vaccinations: vaccinations,
    );
  }
}

final visitSummaryServiceProvider =
    Provider<VisitSummaryService>(VisitSummaryService.new);
