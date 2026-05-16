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

  Future<VisitSummaryData> buildSummary({
    required String babyId,
    required int rangeDays,
  }) async {
    final db = await _ref.read(appDatabaseProvider.future);

    final babies = await _ref.read(babyRepositoryProvider).list();
    final baby = babies.firstWhere(
      (b) => b.id == babyId,
      orElse: () => throw StateError('Baby not found'),
    );

    // Build per-day buckets using LOCAL midnight boundaries so the PDF report
    // assigns events to the correct calendar day for non-UTC timezones (e.g.
    // Thai users at UTC+7). Each day boundary is converted to UTC only when
    // comparing against the UTC ISO strings stored in the DB.
    final nowLocal = DateTime.now();
    final todayLocal = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
    final rangeStartLocal = todayLocal.subtract(Duration(days: rangeDays - 1));
    final rangeEndLocal = todayLocal.add(const Duration(days: 1));

    // UTC strings for the DB WHERE clause
    final rangeStartUtc = rangeStartLocal.toUtc().toIso8601String();
    final rangeEndUtc = rangeEndLocal.toUtc().toIso8601String();

    // Keep local DateTime references for returning in the result envelope
    final rangeStart = rangeStartLocal;
    final rangeEnd = DateTime(nowLocal.year, nowLocal.month, nowLocal.day, 23, 59, 59);

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
      // Use local midnight windows so events are bucketed by the user's calendar
      // day, not by UTC day.
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

    return VisitSummaryData(
      babyName: baby.nickname?.isNotEmpty == true ? baby.nickname! : baby.name,
      babyDob: baby.dob,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      days: days,
      vaccinations: vaccinations,
    );
  }
}

final visitSummaryServiceProvider =
    Provider<VisitSummaryService>(VisitSummaryService.new);
