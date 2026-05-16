import 'package:flutter/foundation.dart';

import '../../../core/services/unit_preferences.dart';

const double _mlPerOz = 29.5735;

String _fmtVol(double oz, VolumeUnit unit) => unit == VolumeUnit.oz
    ? '${oz.toStringAsFixed(1)} oz'
    : '${(oz * _mlPerOz).round()} ml';

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
    required this.pumpOz,
    required this.diaperCount,
    required this.sleepMinutes,
    required this.stashOz,
    required this.babyIsAsleep,
  });

  final double feedOz;
  final int feedCount;
  final int pumpCount;
  final double pumpOz;
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

  String feedFormatted(VolumeUnit unit) {
    if (feedCount == 0) return '—';
    final countLabel = feedCount == 1 ? '1 feed' : '$feedCount feeds';
    return '${_fmtVol(feedOz, unit)} ($countLabel)';
  }

  String stashFormatted(VolumeUnit unit) =>
      stashOz <= 0 ? '—' : _fmtVol(stashOz, unit);
}
