import 'package:dreambook/core/services/unit_preferences.dart';
import 'package:dreambook/features/summary/data/daily_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DailySummary make({
    double feedOz = 0,
    int feedCount = 0,
    int pumpCount = 0,
    double pumpOz = 0,
    int diaperCount = 0,
    int sleepMinutes = 0,
    double stashOz = 0,
    bool babyIsAsleep = false,
  }) =>
      DailySummary(
        feedOz: feedOz,
        feedCount: feedCount,
        pumpCount: pumpCount,
        pumpOz: pumpOz,
        diaperCount: diaperCount,
        sleepMinutes: sleepMinutes,
        stashOz: stashOz,
        babyIsAsleep: babyIsAsleep,
      );

  group('DailySummary.sleepFormatted', () {
    test('returns "—" for 0 minutes', () {
      expect(make(sleepMinutes: 0).sleepFormatted, '—');
    });

    test('returns "45m" for 45 minutes', () {
      expect(make(sleepMinutes: 45).sleepFormatted, '45m');
    });

    test('returns "1h 30m" for 90 minutes', () {
      expect(make(sleepMinutes: 90).sleepFormatted, '1h 30m');
    });
  });

  group('DailySummary.feedFormatted', () {
    test('returns "—" for 0 feeds', () {
      expect(make(feedOz: 0, feedCount: 0).feedFormatted(VolumeUnit.oz), '—');
    });

    test('returns "8.0 oz (3 feeds)" for feedOz=8, feedCount=3 (oz pref)', () {
      expect(
        make(feedOz: 8, feedCount: 3).feedFormatted(VolumeUnit.oz),
        '8.0 oz (3 feeds)',
      );
    });

    test('converts to ml when pref is ml', () {
      // 8 oz × 29.5735 ≈ 237 ml
      expect(
        make(feedOz: 8, feedCount: 3).feedFormatted(VolumeUnit.ml),
        '237 ml (3 feeds)',
      );
    });
  });

  group('DailySummary.stashFormatted', () {
    test('returns "—" for 0 oz', () {
      expect(make(stashOz: 0).stashFormatted(VolumeUnit.oz), '—');
    });

    test('returns "12.5 oz" for 12.5 oz (oz pref)', () {
      expect(make(stashOz: 12.5).stashFormatted(VolumeUnit.oz), '12.5 oz');
    });

    test('converts to ml when pref is ml', () {
      // 12.5 oz × 29.5735 ≈ 370 ml
      expect(make(stashOz: 12.5).stashFormatted(VolumeUnit.ml), '370 ml');
    });
  });
}
