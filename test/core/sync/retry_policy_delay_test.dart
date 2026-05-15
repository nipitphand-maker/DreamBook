import 'dart:math';

import 'package:dreambook/core/sync/retry_policy.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedRandom implements Random {
  _FixedRandom(this.value);
  final double value;
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => value;
  @override
  int nextInt(int max) => 0;
}

void main() {
  group('RetryPolicy.delayFor', () {
    test('attempt 1 with 0 jitter = ~800ms (0.8 factor)', () {
      final d = RetryPolicy.delayFor(1, random: _FixedRandom(0));
      expect(d.inMilliseconds, 800);
    });
    test('attempt 1 with 1.0 jitter = ~1200ms (1.2 factor)', () {
      final d = RetryPolicy.delayFor(1, random: _FixedRandom(1));
      expect(d.inMilliseconds, 1200);
    });
    test('attempt 5 with 0.5 jitter = ~16000ms', () {
      final d = RetryPolicy.delayFor(5, random: _FixedRandom(0.5));
      expect(d.inMilliseconds, 16000);
    });
    test('attempt 6+ caps at attempt-5 base (16s)', () {
      final d = RetryPolicy.delayFor(99, random: _FixedRandom(0.5));
      expect(d.inMilliseconds, 16000);
    });
    test('attempt < 1 returns zero', () {
      expect(RetryPolicy.delayFor(0), Duration.zero);
      expect(RetryPolicy.delayFor(-1), Duration.zero);
    });
    test('attempt 2 with 0.5 jitter = ~2000ms', () {
      final d = RetryPolicy.delayFor(2, random: _FixedRandom(0.5));
      expect(d.inMilliseconds, 2000);
    });
    test('attempt 3 with 0.5 jitter = ~4000ms', () {
      final d = RetryPolicy.delayFor(3, random: _FixedRandom(0.5));
      expect(d.inMilliseconds, 4000);
    });
  });
}
