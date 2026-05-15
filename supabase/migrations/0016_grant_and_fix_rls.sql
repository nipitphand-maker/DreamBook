-- Migration 0016: Fix missing table grants + broken key_distribution RLS.
--
-- Root causes of every sync 403 since Plan C launch:
--
-- Bug 1: encrypted_rows and key_distribution had NO grants to `authenticated`.
--   PostgreSQL checks table-level grants BEFORE evaluating RLS policies.
--   Every Flutter REST call (authenticated user) hit "permission denied"
--   before the well-formed RLS policies were even reached.
--
-- Bug 2: key_distribution RLS policies used uuid_send(auth.uid()) to match
--   device_fp (bytea). But device_fp = SHA-256(pubkey)[0:16], which is
--   completely unrelated to the Supabase user UUID.  The correct join is
--   through family_devices.auth_user_id = auth.uid().

-- ── 1. Table grants ──────────────────────────────────────────────────────────

GRANT SELECT, INSERT, UPDATE ON public.encrypted_rows  TO authenticated;
GRANT SELECT, INSERT        ON public.key_distribution TO authenticated;

-- ── 2. Fix key_distribution SELECT policy ────────────────────────────────────
-- A device may see the wrapped keys that are addressed to its own device_fp.
-- We resolve "which device_fp belongs to this auth user" via family_devices.

DROP POLICY IF EXISTS key_distribution_select_own ON public.key_distribution;
CREATE POLICY key_distribution_select_own
  ON public.key_distribution
  FOR SELECT TO authenticated
  USING (
    recipient_device_fp IN (
      SELECT device_fp FROM public.family_devices
      WHERE auth_user_id = auth.uid()
        AND revoked_at IS NULL
    )
  );

-- ── 3. Fix key_distribution INSERT policy ────────────────────────────────────
-- Only the admin device of the target family may insert wrapped keys.
-- (Key rotation after caregiver revocation — the admin re-wraps for survivors.)

DROP POLICY IF EXISTS key_distribution_insert_admin ON public.key_distribution;
CREATE POLICY key_distribution_insert_admin
  ON public.key_distribution
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.family_devices fd
      WHERE fd.family_id = key_distribution.family_id
        AND fd.auth_user_id = auth.uid()
        AND fd.role = 'admin'
        AND fd.revoked_at IS NULL
    )
  );
