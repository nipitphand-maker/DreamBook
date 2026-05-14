import 'package:dreambook/features/diaper/data/diaper_repository.dart';
import 'package:dreambook/features/feed/data/feed_providers.dart';
import 'package:dreambook/features/feed/data/feed_repository.dart' show feedTodayProvider;
import 'package:dreambook/features/pump/data/pump_providers.dart';
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
