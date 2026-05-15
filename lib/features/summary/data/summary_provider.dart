import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/features/diaper/data/diaper_repository.dart';
import 'package:dreambook/features/feed/data/feed_providers.dart';
import 'package:dreambook/features/feed/data/feed_repository.dart';
import 'package:dreambook/features/pump/data/pump_providers.dart';
import 'package:dreambook/features/pump/data/pump_repository.dart';
import 'package:dreambook/features/sleep/data/sleep_repository.dart';
import 'package:dreambook/features/stash/data/stash_providers.dart';
import 'package:dreambook/features/summary/data/daily_summary.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  final diaperCount = ref.watch(diaperCountTodayProvider(babyId));
  final sleepMin = ref.watch(sleepMinutesTodayProvider(babyId));
  final stashOz = ref.watch(stashTotalOzProvider(babyId));
  final sleepActive = ref.watch(sleepActiveProvider(babyId));

  final all = [
    feedOz,
    feedList,
    pumpCount,
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
  return ref.read(feedRepositoryProvider).todayFor(babyId, now: date);
});

final _diaperForDateProvider =
    FutureProvider.family<List<Diaper>, (String, String)>((ref, p) async {
  final (babyId, dateStr) = p;
  ref.watch(appDatabaseProvider);
  final date = DateTime.parse(dateStr);
  return ref.read(diaperRepositoryProvider).todayFor(babyId, now: date);
});

final _sleepForDateProvider =
    FutureProvider.family<List<Sleep>, (String, String)>((ref, p) async {
  final (babyId, dateStr) = p;
  ref.watch(appDatabaseProvider);
  final date = DateTime.parse(dateStr);
  return ref.read(sleepRepositoryProvider).todayFor(babyId, now: date);
});

final _pumpForDateProvider =
    FutureProvider.family<List<PumpSession>, (String, String)>((ref, p) async {
  final (babyId, dateStr) = p;
  ref.watch(appDatabaseProvider);
  final date = DateTime.parse(dateStr);
  return ref.read(pumpRepositoryProvider).todayFor(babyId, now: date);
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

  return AsyncValue.data(DailySummary(
    feedOz: feedOz,
    feedCount: feeds.length,
    pumpCount: pumps.length,
    diaperCount: diapers.length,
    sleepMinutes: sleepMin,
    stashOz: 0, // stash is not date-scoped
    babyIsAsleep: false, // only meaningful for today
  ));
});
