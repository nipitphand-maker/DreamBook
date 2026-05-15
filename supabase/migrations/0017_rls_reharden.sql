-- supabase/migrations/0017_rls_reharden.sql
-- Restore the encrypted_rows write guards that migration 0011 dropped, and
-- add retention/last-active columns + indexes for the §5.1 spec items.
-- See spec docs/superpowers/specs/2026-05-15-dreambook-sync-recovery-hardening-design.md §5.1.

BEGIN;

-- 1. families: retention + activity columns (§7.5 SSI-3, §7.4 cold-tier).
ALTER TABLE public.families
  ADD COLUMN IF NOT EXISTS tombstone_retention_days int NOT NULL DEFAULT 90,
  ADD COLUMN IF NOT EXISTS last_active_at           timestamptz;

-- 2. encrypted_rows INSERT — restore written_by_device + key_version guards.
DROP POLICY IF EXISTS encrypted_rows_insert ON public.encrypted_rows;
CREATE POLICY encrypted_rows_insert ON public.encrypted_rows
  FOR INSERT TO authenticated
  WITH CHECK (
    family_id IN (SELECT public.current_user_family_ids())
    AND written_by_device = (
      SELECT encode(device_fp, 'hex')
      FROM public.family_devices
      WHERE auth_user_id = auth.uid()
        AND family_id    = encrypted_rows.family_id
        AND revoked_at IS NULL
      LIMIT 1
    )
    AND key_version = (
      SELECT current_key_version
      FROM public.families
      WHERE id = encrypted_rows.family_id
    )
  );

-- 3. encrypted_rows UPDATE — only the writing device can update its own row.
DROP POLICY IF EXISTS encrypted_rows_update ON public.encrypted_rows;
CREATE POLICY encrypted_rows_update ON public.encrypted_rows
  FOR UPDATE TO authenticated
  USING (
    family_id IN (SELECT public.current_user_family_ids())
    AND written_by_device = (
      SELECT encode(device_fp, 'hex')
      FROM public.family_devices
      WHERE auth_user_id = auth.uid()
        AND family_id    = encrypted_rows.family_id
        AND revoked_at IS NULL
      LIMIT 1
    )
  )
  WITH CHECK (
    family_id IN (SELECT public.current_user_family_ids())
  );

-- 4. Explicit grants (table-level grants run BEFORE RLS — see 0016 root cause).
GRANT SELECT ON public.families        TO authenticated;
GRANT SELECT ON public.family_devices  TO authenticated;

-- 5. Indexes — kill the table-scan that every encrypted_rows access triggers.
CREATE INDEX IF NOT EXISTS family_devices_auth_user_id_idx
  ON public.family_devices(auth_user_id)
  WHERE auth_user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS family_devices_device_fp_active_idx
  ON public.family_devices(device_fp)
  WHERE auth_user_id IS NOT NULL AND revoked_at IS NULL;

-- 6. Data-integrity invariant: at most one ACTIVE device per (auth_user_id, family_id).
-- Without this, the LIMIT 1 subqueries above could silently pick an arbitrary row
-- if duplicates existed, masking a spoof. This index makes the duplicate impossible.
CREATE UNIQUE INDEX IF NOT EXISTS family_devices_one_active_per_user_family
  ON public.family_devices(auth_user_id, family_id)
  WHERE auth_user_id IS NOT NULL AND revoked_at IS NULL;

COMMIT;
