import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/providers/day_start_hour_provider.dart';
import 'package:dreambook/features/diaper/data/diaper_repository.dart';
import 'package:dreambook/features/feed/data/feed_providers.dart';
import 'package:dreambook/features/feed/data/feed_repository.dart';
import 'package:dreambook/features/pump/data/pump_providers.dart';
import 'package:dreambook/features/pump/data/pump_repository.dart';
import 'package:dreambook/features/sleep/data/sleep_repository.dart';
import 'package:dreambook/features/stash/data/stash_providers.dart';
import 'package:dreambook/features/summary/data/daily_summary.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

export 'daily_summary.dart';

/// Combines all today-stats for [babyId] into a single [DailySummary].
///
/// Returns [AsyncLoading] while any upstream provider is still loading, and
/// surfaces the first [AsyncError] encountered if any provider fails.
/// This lets the UI do a single `.when()` call instead of seven.
final dailySummaryProvider =
    Provider.family<AsyncValue<DailySummary>, String>((ref, babyId) {
  final feedOz = ref.watch(feedOzTodayProvider(babyId));
  final feedList = ref.watch(feedTodayProvider(babyId));
  final pumpCount = ref.watch(pumpCountTodayProvider(babyId));
  final pumpOz = ref.watch(pumpOzTodayProvider(babyId));
  final diaperCount = ref.watch(diaperCountTodayProvider(babyId));
  final sleepMin = ref.watch(sleepMinutesTodayProvider(babyId));
  final stashOz = ref.watch(stashTotalOzProvider(babyId));
  final sleepActive = ref.watch(sleepActiveProvider(babyId));

  final all = [
    feedOz,
    feedList,
    pumpCount,
    pumpOz,
    diaperCount,
    sleepMin,
    stashOz,
    sleepActive,
  ];

  if (all.any((v) => v is AsyncLoading)) {
    return const AsyncValue.loading();
  }

  final err = all.whereType<AsyncError<dynamic>>().firstOrNull;
  if (err != null) {
    return AsyncValue.error(err.error, err.stackTrace);
  }

  return AsyncValue.data(DailySummary(
    feedOz: feedOz.value ?? 0,
    feedCount: feedList.value?.length ?? 0,
    pumpCount: pumpCount.value ?? 0,
    pumpOz: pumpOz.value ?? 0,
    diaperCount: diaperCount.value ?? 0,
    sleepMinutes: sleepMin.value ?? 0,
    stashOz: stashOz.value ?? 0,
    babyIsAsleep: sleepActive.value != null,
  ));
});

// ── Date-parameterised providers used by the Summary date-picker ────────────
// All take (babyId, dateStr) where dateStr = "YYYY-MM-DD" in local time.

final feedForDateProvider =
    FutureProvider.family<List<Feed>, (String, String)>((ref, p) async {
  final (babyId, dateStr) = p;
  ref.watch(appDatabaseProvider);
  final date = DateTime.parse(dateStr);
  final dayStartHour = ref.read(dayStartHourProvider);
  return ref
      .read(feedRepositoryProvider)
      .todayFor(babyId, now: date, dayStartHour: dayStartHour);
});

final _diaperForDateProvider =
    FutureProvider.family<List<Diaper>, (String, String)>((ref, p) async {
  final (babyId, dateStr) = p;
  ref.watch(appDatabaseProvider);
  final date = DateTime.parse(dateStr);
  final dayStartHour = ref.read(dayStartHourProvider);
  return ref
      .read(diaperRepositoryProvider)
      .todayFor(babyId, now: date, dayStartHour: dayStartHour);
});

final _sleepForDateProvider =
    FutureProvider.family<List<Sleep>, (String, String)>((ref, p) async {
  final (babyId, dateStr) = p;
  ref.watch(appDatabaseProvider);
  final date = DateTime.parse(dateStr);
  final dayStartHour = ref.read(dayStartHourProvider);
  return ref
      .read(sleepRepositoryProvider)
      .todayFor(babyId, now: date, dayStartHour: dayStartHour);
});

final _pumpForDateProvider =
    FutureProvider.family<List<PumpSession>, (String, String)>((ref, p) async {
  final (babyId, dateStr) = p;
  ref.watch(appDatabaseProvider);
  final date = DateTime.parse(dateStr);
  final dayStartHour = ref.read(dayStartHourProvider);
  return ref
      .read(pumpRepositoryProvider)
      .todayFor(babyId, now: date, dayStartHour: dayStartHour);
});

// ── Activity-day index for the Summary calendar picker ─────────────────────
// Given (babyId, year, month), returns the set of local YYYY-MM-DD dates
// in that month that have at least one non-deleted activity row across
// feed / pump_session / diaper / sleep / stash_bottle. Used to render
// "has activity" dots in the history calendar.
//
// We do the work in SQL — five SELECTs against the live tables — instead of
// fetching every row and bucketing in Dart. SQLite's `date(ts, 'localtime')`
// converts the ISO-8601 UTC timestamp we store into the device's local
// calendar date, which is what the user thinks of as "the day".
//
// Note: this provider is intentionally NOT invalidated by the sync layer's
// `onAfterPull` hook today (the sync controller is owned by another team).
// It watches `appDatabaseProvider`, so a DB swap or app-relaunch refreshes
// it. Day-level activity flips infrequently enough that this is fine; we
// can wire incremental invalidation in a follow-up if it becomes a problem.

/// Set of local YYYY-MM-DD dates with any logged activity in the given
/// (babyId, year, month). `month` is 1–12.
final summaryActivityDaysProvider =
    FutureProvider.family<Set<String>, (String, int, int)>((ref, params) async {
  final (babyId, year, month) = params;
  final db = await ref.watch(appDatabaseProvider.future);

  // Half-open [monthStart, monthEnd) range in LOCAL time, converted to UTC
  // ISO strings for the WHERE clause against UTC-stored started_at columns.
  // We over-fetch slightly (one day either side) so timestamps near local
  // midnight that round to the previous/next UTC day still get matched —
  // SQLite's `date(..., 'localtime')` filter narrows the final result.
  final monthStartLocal = DateTime(year, month, 1);
  final monthEndLocal = DateTime(year, month + 1, 1);
  final fromUtc = monthStartLocal
      .subtract(const Duration(days: 1))
      .toUtc()
      .toIso8601String();
  final toUtc =
      monthEndLocal.add(const Duration(days: 1)).toUtc().toIso8601String();

  // Build a UNION ALL across the five activity tables. Each branch projects
  // a single column `d` = local YYYY-MM-DD. DISTINCT at the top dedups.
  // `started_at`, `occurred_at`, and `pumped_at` are the canonical anchors
  // per table — see `lib/core/db/migrations/m001_initial.dart`.
  final monthPrefix = '$year-${month.toString().padLeft(2, '0')}';
  final rows = await db.rawQuery(
    '''
    SELECT DISTINCT d FROM (
      SELECT date(started_at, 'localtime') AS d
      FROM feed
      WHERE baby_id = ? AND deleted_at IS NULL
        AND started_at >= ? AND started_at < ?
      UNION ALL
      SELECT date(started_at, 'localtime') AS d
      FROM pump_session
      WHERE baby_id = ? AND deleted_at IS NULL
        AND started_at >= ? AND started_at < ?
      UNION ALL
      SELECT date(occurred_at, 'localtime') AS d
      FROM diaper
      WHERE baby_id = ? AND deleted_at IS NULL
        AND occurred_at >= ? AND occurred_at < ?
      UNION ALL
      SELECT date(started_at, 'localtime') AS d
      FROM sleep
      WHERE baby_id = ? AND deleted_at IS NULL
        AND started_at >= ? AND started_at < ?
      UNION ALL
      SELECT date(pumped_at, 'localtime') AS d
      FROM stash_bottle
      WHERE baby_id = ? AND deleted_at IS NULL
        AND pumped_at >= ? AND pumped_at < ?
    )
    WHERE d LIKE ?
    ''',
    [
      babyId, fromUtc, toUtc, // feed
      babyId, fromUtc, toUtc, // pump_session
      babyId, fromUtc, toUtc, // diaper
      babyId, fromUtc, toUtc, // sleep
      babyId, fromUtc, toUtc, // stash_bottle
      '$monthPrefix-%',
    ],
  );

  return rows
      .map((r) => r['d'] as String?)
      .whereType<String>()
      .toSet();
});

/// Summary for any calendar date. Uses FutureProvider-backed queries so past
/// dates are non-reactive (immutable historical data).
final dailySummaryForDateProvider =
    Provider.family<AsyncValue<DailySummary>, (String, String)>(
        (ref, params) {
  final feedList = ref.watch(feedForDateProvider(params));
  final diaperList = ref.watch(_diaperForDateProvider(params));
  final sleepList = ref.watch(_sleepForDateProvider(params));
  final pumpList = ref.watch(_pumpForDateProvider(params));

  final all = [feedList, diaperList, sleepList, pumpList];
  if (all.any((v) => v is AsyncLoading)) return const AsyncValue.loading();
  final err = all.whereType<AsyncError<dynamic>>().firstOrNull;
  if (err != null) return AsyncValue.error(err.error, err.stackTrace);

  final feeds = feedList.value!;
  final diapers = diaperList.value!;
  final sleeps = sleepList.value!;
  final pumps = pumpList.value!;

  final feedOz =
      feeds.fold<double>(0.0, (double s, Feed f) => s + (f.oz ?? 0.0));
  final sleepMin =
      sleeps.fold<int>(0, (int s, Sleep sl) => s + (sl.durationMin ?? 0));
  final pumpOz = pumps.fold<double>(
      0.0, (double s, PumpSession p) => s + p.leftOz + p.rightOz);

  return AsyncValue.data(DailySummary(
    feedOz: feedOz,
    feedCount: feeds.length,
    pumpCount: pumps.length,
    pumpOz: pumpOz,
    diaperCount: diapers.length,
    sleepMinutes: sleepMin,
    stashOz: 0, // stash is not date-scoped
    babyIsAsleep: false, // only meaningful for today
  ));
});

// ── Range provider ──────────────────────────────────────────────────────────
// Params: (babyId, fromCutoff, toExclCutoff) — both are EXACT local-time
// DateTime cutoffs already aligned to the user's dayStartHour boundary by
// the caller (see _rangeForPeriod). Provider just converts to UTC ISO for
// SQL comparison.

/// Aggregated [DailySummary] totals for the half-open range
/// `[fromCutoff, toExclCutoff)`.
///
/// The caller is responsible for aligning the cutoffs to the user's
/// dayStartHour so this matches the Today-view bucketing. [stashOz] is
/// the current stash total (not date-scoped).
final summaryForRangeProvider =
    FutureProvider.family<DailySummary, (String, DateTime, DateTime)>(
        (ref, params) async {
  final (babyId, fromCutoff, toExclCutoff) = params;
  ref.watch(appDatabaseProvider);
  final db = await ref.read(appDatabaseProvider.future);

  final fromStr = fromCutoff.toUtc().toIso8601String();
  final toExclStr = toExclCutoff.toUtc().toIso8601String();

  // Feed totals
  final feedRows = await db.rawQuery(
    '''
    SELECT COUNT(*) AS cnt, COALESCE(SUM(oz), 0.0) AS total_oz
    FROM feed
    WHERE baby_id = ?
      AND deleted_at IS NULL
      AND started_at >= ?
      AND started_at < ?
    ''',
    [babyId, fromStr, toExclStr],
  );
  final feedCount = (feedRows.first['cnt'] as num?)?.toInt() ?? 0;
  final feedOz = (feedRows.first['total_oz'] as num?)?.toDouble() ?? 0.0;

  // Pump totals
  final pumpRows = await db.rawQuery(
    'SELECT COUNT(*) AS cnt, COALESCE(SUM(left_oz + right_oz), 0.0) AS total_oz FROM pump_session WHERE baby_id = ? AND deleted_at IS NULL AND started_at >= ? AND started_at < ?',
    [babyId, fromStr, toExclStr],
  );
  final pumpCount = (pumpRows.first['cnt'] as num?)?.toInt() ?? 0;
  final pumpOzRange = (pumpRows.first['total_oz'] as num?)?.toDouble() ?? 0.0;

  // Diaper totals
  final diaperCount = Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM diaper WHERE baby_id = ? AND deleted_at IS NULL AND occurred_at >= ? AND occurred_at < ?',
          [babyId, fromStr, toExclStr],
        ),
      ) ??
      0;

  // Sleep totals (sum of duration_min for completed sessions)
  final sleepRows = await db.rawQuery(
    'SELECT COALESCE(SUM(duration_min), 0) AS total_min FROM sleep WHERE baby_id = ? AND deleted_at IS NULL AND started_at >= ? AND started_at < ? AND duration_min IS NOT NULL',
    [babyId, fromStr, toExclStr],
  );
  final sleepMinutes = (sleepRows.first['total_min'] as num?)?.toInt() ?? 0;

  // Current stash (not date-scoped)
  final stashAsync = ref.read(stashTotalOzProvider(babyId));
  final stashOz = stashAsync.value ?? 0.0;

  return DailySummary(
    feedOz: feedOz,
    feedCount: feedCount,
    pumpCount: pumpCount,
    pumpOz: pumpOzRange,
    diaperCount: diaperCount,
    sleepMinutes: sleepMinutes,
    stashOz: stashOz,
    babyIsAsleep: false,
  );
});
