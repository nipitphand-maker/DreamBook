import 'package:dreambook/core/observability/sentry_init.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  group('Sentry scrubber (_scrub)', () {
    test('redacts ciphertext field', () {
      final event =
          SentryEvent(extra: {'ciphertext': 'AABBCC', 'message': 'ok'});
      final scrubbed = sentryBeforeSendForTest(event, Hint());
      expect(scrubbed!.extra!['ciphertext'], '[REDACTED]');
      expect(scrubbed.extra!['message'], 'ok');
    });

    test('redacts wrapped_key field', () {
      final event =
          SentryEvent(extra: {'wrapped_key': 'secret', 'count': 42});
      final scrubbed = sentryBeforeSendForTest(event, Hint());
      expect(scrubbed!.extra!['wrapped_key'], '[REDACTED]');
      expect(scrubbed.extra!['count'], 42);
    });

    test('redacts fields ending in _key or _fp', () {
      final event = SentryEvent(
          extra: {'session_key': 'x', 'device_fp': 'y', 'name': 'z'});
      final scrubbed = sentryBeforeSendForTest(event, Hint());
      expect(scrubbed!.extra!['session_key'], '[REDACTED]');
      expect(scrubbed.extra!['device_fp'], '[REDACTED]');
      expect(scrubbed.extra!['name'], 'z');
    });

    test('null extra returns event unchanged', () {
      final event = SentryEvent();
      final scrubbed = sentryBeforeSendForTest(event, Hint());
      expect(scrubbed, isNotNull);
      expect(scrubbed!.extra, isNull);
    });
  });
}
