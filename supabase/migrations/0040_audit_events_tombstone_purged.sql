-- Add tombstone_purged to audit_events CHECK and extend default tombstone
-- retention from 90 to 365 days.
--
-- cleanup_tombstones EF had a TODO to use 'tombstone_purged' once the event
-- type was added to the CHECK constraint (0033 added 'compaction_completed'
-- for compact_encrypted_rows but left tombstone_purged pending).
--
-- Also extend tombstone_retention_days default from 90 → 365 to retain
-- deleted-row markers long enough for devices that go offline for months
-- (e.g. a spare phone sitting in a drawer) to sync correctly before data
-- is permanently purged.

BEGIN;

-- 1. Add tombstone_purged to the CHECK constraint.
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
    'recovery_code_registered', 'compaction_completed',
    'tombstone_purged'
  ));

-- 2. Extend default tombstone retention from 90 days to 365 days.
ALTER TABLE public.families
  ALTER COLUMN tombstone_retention_days SET DEFAULT 365;

-- Backfill existing families that still have the old 90-day default.
UPDATE public.families
  SET tombstone_retention_days = 365
WHERE tombstone_retention_days = 90;

COMMIT;
