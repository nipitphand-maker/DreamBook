import 'dart:io';

import 'package:dreambook/core/sync/retry_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  Duration zeroDelay(int attempt) => Duration.zero;
  Future<void> noSleep(Duration d) async {}

  group('RetryPolicy.run', () {
    test('returns result on first-attempt success', () async {
      final r = await RetryPolicy.run<int>(
        () async => 42,
        delayFn: zeroDelay,
        sleep: noSleep,
      );
      expect(r, 42);
    });

    test('retries transient up to maxAttempts then throws last error', () async {
      var calls = 0;
      await expectLater(
        RetryPolicy.run<int>(
          () async {
            calls++;
            throw const SocketException('down');
          },
          delayFn: zeroDelay,
          sleep: noSleep,
        ),
        throwsA(isA<SocketException>()),
      );
      expect(calls, 5);
    });

    test('rethrows terminal error on first attempt without retrying', () async {
      var calls = 0;
      await expectLater(
        RetryPolicy.run<int>(
          () async {
            calls++;
            throw const PostgrestException(message: 'bad', code: '400');
          },
          delayFn: zeroDelay,
          sleep: noSleep,
        ),
        throwsA(isA<PostgrestException>()),
      );
      expect(calls, 1);
    });

    test('succeeds on attempt 3 after two transient failures', () async {
      var calls = 0;
      final r = await RetryPolicy.run<int>(
        () async {
          calls++;
          if (calls < 3) throw const SocketException('flaky');
          return 99;
        },
        delayFn: zeroDelay,
        sleep: noSleep,
      );
      expect(r, 99);
      expect(calls, 3);
    });

    test('delayFn is called with attempts 1..4 before final attempt 5 fails',
        () async {
      final attempts = <int>[];
      await expectLater(
        RetryPolicy.run<int>(
          () async {
            throw const SocketException('down');
          },
          delayFn: (a) {
            attempts.add(a);
            return Duration.zero;
          },
          sleep: noSleep,
        ),
        throwsA(isA<SocketException>()),
      );
      // Five attempts total; delay is only scheduled BEFORE retries 2..5,
      // i.e. called with attempt numbers 1, 2, 3, 4 (no delay after final).
      expect(attempts, [1, 2, 3, 4]);
    });
  });
}
