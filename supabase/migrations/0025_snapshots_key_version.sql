-- supabase/migrations/0025_snapshots_key_version.sql
-- encrypted_snapshots was missing key_version — restore_snapshot needs it to
-- return the correct version to the client for SnapshotService.restore().
BEGIN;
ALTER TABLE public.encrypted_snapshots
  ADD COLUMN IF NOT EXISTS key_version int NOT NULL DEFAULT 1;
COMMIT;
