/// Identifies why a sync cycle was triggered.
enum SyncTrigger { realtime, foreground, networkResume, postWrite, background }

extension SyncTriggerAudit on SyncTrigger {
  /// Returns the audit event_type string for this trigger, or null if no
  /// audit event should be emitted for this trigger type.
  String? get auditEventType => switch (this) {
        SyncTrigger.background => 'sync_background_started',
        _ => null,
      };
}
