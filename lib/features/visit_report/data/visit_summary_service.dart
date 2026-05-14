import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/features/baby/data/baby_repository.dart';
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

    final now = DateTime.now().toUtc();
    final rangeEnd = DateTime.utc(now.year, now.month, now.day, 23, 59, 59);
    final rangeStart = DateTime.utc(now.year, now.month, now.day)
        .subtract(Duration(days: rangeDays - 1));

    final feedRows = await db.query(
      'feed',
      where:
          'baby_id = ? AND deleted_at IS NULL AND started_at >= ? AND started_at <= ?',
      whereArgs: [
        babyId,
        rangeStart.toIso8601String(),
        rangeEnd.toIso8601String(),
      ],
    );
    final feeds = feedRows.map(Feed.fromRow).toList();

    final diaperRows = await db.query(
      'diaper',
      where:
          'baby_id = ? AND deleted_at IS NULL AND occurred_at >= ? AND occurred_at <= ?',
      whereArgs: [
        babyId,
        rangeStart.toIso8601String(),
        rangeEnd.toIso8601String(),
      ],
    );
    final diapers = diaperRows.map(Diaper.fromRow).toList();

    final sleepRows = await db.query(
      'sleep',
      where:
          'baby_id = ? AND deleted_at IS NULL AND started_at >= ? AND started_at <= ?',
      whereArgs: [
        babyId,
        rangeStart.toIso8601String(),
        rangeEnd.toIso8601String(),
      ],
    );
    final sleeps = sleepRows.map(Sleep.fromRow).toList();

    final vaccinations =
        await _ref.read(vaccinationRepositoryProvider).listFor(babyId);

    final days = <DaySummary>[];
    for (var i = 0; i < rangeDays; i++) {
      final dayStart = rangeStart.add(Duration(days: i));
      final dayEnd = dayStart.add(const Duration(days: 1));

      final dayFeeds = feeds
          .where((f) =>
              !f.startedAt.isBefore(dayStart) && f.startedAt.isBefore(dayEnd))
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
