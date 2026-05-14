import 'package:flutter/foundation.dart';

/// Aggregated today-stats for one baby.
///
/// Pure data class — no Riverpod, no DB. Constructed by [dailySummaryProvider]
/// from the individual feature providers.
@immutable
class DailySummary {
  const DailySummary({
    required this.feedOz,
    required this.feedCount,
    required this.pumpCount,
    required this.diaperCount,
    required this.sleepMinutes,
    required this.stashOz,
    required this.babyIsAsleep,
  });

  final double feedOz;
  final int feedCount;
  final int pumpCount;
  final int diaperCount;
  final int sleepMinutes;
  final double stashOz;
  final bool babyIsAsleep;

  String get sleepFormatted {
    if (sleepMinutes == 0) return '—';
    final h = sleepMinutes ~/ 60;
    final m = sleepMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  String get feedFormatted =>
      feedCount == 0 ? '—' : '${feedOz.toStringAsFixed(1)} oz ($feedCount feeds)';

  String get stashFormatted =>
      stashOz <= 0 ? '—' : '${stashOz.toStringAsFixed(1)} oz';
}
