import 'package:dreambook/core/sync/sync_trigger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyncTrigger.auditEventType', () {
    test('background trigger maps to sync_background_started', () {
      expect(SyncTrigger.background.auditEventType, 'sync_background_started');
    });

    test('non-background triggers return null', () {
      for (final t in [
        SyncTrigger.realtime,
        SyncTrigger.foreground,
        SyncTrigger.networkResume,
        SyncTrigger.postWrite,
      ]) {
        expect(t.auditEventType, isNull, reason: '${t.name} should return null');
      }
    });
  });
}
