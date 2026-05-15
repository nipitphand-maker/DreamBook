-- supabase/migrations/0026_fix_families_select_uuid_send_bug.sql
--
-- The original families_select policy compared:
--   family_devices.device_fp = uuid_send(auth.uid())
-- which is the exact bug migration 0011 documented for the encrypted_rows
-- policies — device_fp is SHA-256(pubkey)[0:16] (16 bytes), and
-- uuid_send(auth.uid()) is the 16-byte UUID. Two unrelated values, never equal.
--
-- Symptom: authenticated users could not SELECT their own family row, which
-- caused the encrypted_rows_insert WITH CHECK subquery
--   key_version = (SELECT current_key_version FROM families WHERE id = …)
-- to return NULL → `1 = NULL` → INSERT denied with RLS 42501. Sync never
-- pushed any rows even though every other identifier (device_fp, auth_user_id,
-- family_id) was correctly aligned client- and server-side.
--
-- Migration 0016 fixed the same pattern in key_distribution policies and
-- 0017 fixed it in encrypted_rows_insert/update — but the families_select
-- policy was missed.
--
-- Fix: replace the broken comparison with a SELECT against
-- public.current_user_family_ids(), the canonical "what families does
-- this caller belong to" helper. This keeps the SECURITY DEFINER lookup
-- centralised and prevents the join from ever drifting again.

BEGIN;

DROP POLICY IF EXISTS families_select ON public.families;

CREATE POLICY families_select ON public.families
  FOR SELECT
  USING (id IN (SELECT public.current_user_family_ids()));

COMMIT;
