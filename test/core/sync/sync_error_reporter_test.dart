import 'package:dreambook/core/sync/sync_error_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyncErrorReporter', () {
    test('captures error with truncated message + stable stack hash', () {
      final r = SyncErrorReporter();
      // Use StateError (public runtimeType) — Dart's `Exception(...)` factory
      // returns a private `_Exception` whose runtimeType.toString() is the
      // mangled name, which would make the assertion fragile across SDKs.
      final ev = r.report(StateError('boom'), StackTrace.current);
      expect(ev.errorType, 'StateError');
      expect(ev.message, contains('boom'));
      expect(ev.stackHash, hasLength(16));
      expect(ev.category, SyncErrorCategory.unknown);
    });

    test('uses provided category', () {
      final r = SyncErrorReporter();
      final ev = r.report(
        StateError('x'),
        StackTrace.current,
        category: SyncErrorCategory.terminal,
      );
      expect(ev.category, SyncErrorCategory.terminal);
    });

    test('buffers up to 100 events then drops oldest', () {
      final r = SyncErrorReporter();
      for (var i = 0; i < 105; i++) {
        r.report(Exception('e$i'), StackTrace.current);
      }
      expect(r.buffered, hasLength(100));
      expect(
        r.buffered.first.message,
        contains('e5'),
        reason: 'oldest 5 events dropped',
      );
    });

    test('truncates messages over 256 chars', () {
      final r = SyncErrorReporter();
      final long = 'x' * 1000;
      final ev = r.report(Exception(long), StackTrace.current);
      expect(ev.message.length, lessThanOrEqualTo(256));
      expect(ev.message, endsWith('...'));
    });

    test('calls onError callback if provided', () {
      SyncErrorEvent? captured;
      final r = SyncErrorReporter(onError: (e) => captured = e);
      r.report(Exception('hook'), StackTrace.current);
      expect(captured, isNotNull);
      expect(captured!.message, contains('hook'));
    });

    test('clear() empties buffer', () {
      final r = SyncErrorReporter();
      r.report(Exception('one'), StackTrace.current);
      r.clear();
      expect(r.buffered, isEmpty);
    });
  });
}
