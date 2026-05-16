-- Add 'recovery_code_registered' and 'compaction_completed' to the
-- audit_events.event_type CHECK constraint.
-- Drop + recreate is the only portable way to extend a CHECK constraint in Postgres.
BEGIN;

ALTER TABLE public.audit_events
  DROP CONSTRAINT IF EXISTS audit_events_event_type_check;

ALTER TABLE public.audit_events
  ADD CONSTRAINT audit_events_event_type_check
  CHECK (event_type IN (
    'family_created', 'invite_created', 'invite_claimed', 'invite_failed',
    'device_revoked', 'key_rotated', 'snapshot_uploaded', 'snapshot_restored',
    'recovery_attempted', 'recovery_succeeded', 'support_action', 'erasure_requested',
    'count_attestation_mismatch',
    'sync_background_started', 'sync_background_finished', 'realtime_reconnected',
    'recovery_code_registered', 'compaction_completed'
  ));

COMMIT;
