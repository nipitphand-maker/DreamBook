import 'package:dreambook/core/sync/sync_status_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyncStatusProvider', () {
    test('initial state is idle, no error', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final state = container.read(syncStatusProvider);
      expect(state.inFlight, isFalse);
      expect(state.lastError, isNull);
      expect(state.lastSyncedAt, isNull);
    });

    test('transitions in-flight → success updates lastSyncedAt', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(syncStatusProvider.notifier);
      notifier.startSync();
      expect(container.read(syncStatusProvider).inFlight, isTrue);
      final t = DateTime.utc(2026, 5, 14, 12);
      notifier.completeSync(at: t);
      final s = container.read(syncStatusProvider);
      expect(s.inFlight, isFalse);
      expect(s.lastSyncedAt, t);
      expect(s.lastError, isNull);
    });
  });
}
