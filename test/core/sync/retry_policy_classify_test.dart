import 'dart:async';
import 'dart:io';

import 'package:dreambook/core/sync/retry_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('RetryPolicy.classify', () {
    test('SocketException is transient', () {
      expect(
        RetryPolicy.classify(const SocketException('down')),
        RetryClass.transient,
      );
    });
    test('TimeoutException is transient', () {
      expect(
        RetryPolicy.classify(TimeoutException('slow')),
        RetryClass.transient,
      );
    });
    test('PostgrestException PGRST204 is transient', () {
      const e = PostgrestException(message: 'no rows', code: 'PGRST204');
      expect(RetryPolicy.classify(e), RetryClass.transient);
    });
    test('PostgrestException 500 is transient', () {
      const e = PostgrestException(message: 'server error', code: '500');
      expect(RetryPolicy.classify(e), RetryClass.transient);
    });
    test('PostgrestException 4xx (not 408/429) is terminal', () {
      const e = PostgrestException(message: 'bad request', code: '400');
      expect(RetryPolicy.classify(e), RetryClass.terminal);
    });
    test('PostgrestException 408 is transient (request timeout)', () {
      const e = PostgrestException(message: 'timeout', code: '408');
      expect(RetryPolicy.classify(e), RetryClass.transient);
    });
    test('PostgrestException 429 is transient (rate limited)', () {
      const e = PostgrestException(message: 'rate', code: '429');
      expect(RetryPolicy.classify(e), RetryClass.transient);
    });
    test('TypeError is terminal', () {
      expect(RetryPolicy.classify(TypeError()), RetryClass.terminal);
    });
    test('unknown error is terminal (fail loud)', () {
      expect(RetryPolicy.classify(Exception('???')), RetryClass.terminal);
    });
  });
}
