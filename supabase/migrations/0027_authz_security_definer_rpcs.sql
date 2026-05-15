-- supabase/migrations/0027_authz_security_definer_rpcs.sql
--
-- Three SECURITY DEFINER RPCs were callable by any anonymous caller and either
-- skipped or trusted caller identity:
--
--   RISK-5 (HIGH)   revoke_caregiver_atomic(p_caller_device_fp, p_target)
--     — trusted p_caller_device_fp without checking that the row's
--       auth_user_id matched the JWT's auth.uid(). An anon user could pass
--       any admin's fingerprint and revoke caregivers in that family.
--
--   RISK-6 (HIGH)   right_to_be_forgotten(p_family_id)
--     — no caller check at all. Any caller with EXECUTE could erase any
--       family by passing its UUID. ACL granted EXECUTE to PUBLIC.
--
--   RISK-3 (MEDIUM) compact_family_versions(p_family_id)
--     — accepts caller-supplied family_id, deletes from encrypted_rows. ACL
--       granted EXECUTE to PUBLIC. Cross-family poking + DoS surface.
--
-- These are orthogonal to the families_select RLS bug closed in 0026 — that
-- bug was a comparison error; these are missing-authorization defects.
--
-- This migration:
--   (1) Adds auth.uid() binding to revoke_caregiver_atomic (caller's
--       device row must have auth_user_id = auth.uid()).
--   (2) Adds an admin-membership precondition to right_to_be_forgotten.
--   (3) Locks compact_family_versions to service_role only.
--   (4) Revokes EXECUTE from PUBLIC/anon on all three; grants only the
--       minimum needed (authenticated for #1 #2, service_role for #3).
--
-- Behavior preserved for legitimate callers. Function bodies otherwise
-- unchanged — see migration 0023 (RTBF body), the original
-- revoke_caregiver_atomic, and 0022 (compaction body) for prior state.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) revoke_caregiver_atomic — bind p_caller_device_fp to auth.uid()
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.revoke_caregiver_atomic(
  p_caller_device_fp bytea,
  p_target_device_fp bytea
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_caller    public.family_devices%rowtype;
  v_target    public.family_devices%rowtype;
  v_new_version int;
  v_survivors json;
BEGIN
  -- Auth gate: the caller's device row must exist AND belong to the current
  -- JWT's auth.uid(). Previously this only checked role='admin', allowing
  -- any anon to spoof a known admin's device_fp.
  SELECT * INTO v_caller
  FROM public.family_devices
  WHERE device_fp = p_caller_device_fp
    AND auth_user_id = auth.uid()
    AND revoked_at IS NULL;
  IF NOT FOUND OR v_caller.role <> 'admin' THEN
    RAISE EXCEPTION '403' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_target
  FROM public.family_devices
  WHERE device_fp = p_target_device_fp;
  IF NOT FOUND OR v_target.family_id <> v_caller.family_id THEN
    RAISE EXCEPTION '404' USING ERRCODE = 'P0002';
  END IF;
  IF v_target.device_fp = v_caller.device_fp THEN
    RAISE EXCEPTION '409' USING ERRCODE = '22023';
  END IF;

  UPDATE public.family_devices
    SET revoked_at = now(), wipe_requested_at = now()
  WHERE device_fp = p_target_device_fp;

  UPDATE public.families
    SET current_key_version = current_key_version + 1
  WHERE id = v_caller.family_id
  RETURNING current_key_version INTO v_new_version;

  SELECT json_agg(json_build_object(
    'device_fp',      encode(device_fp, 'base64'),
    'device_pub_key', encode(device_pub_key, 'base64')
  )) INTO v_survivors
  FROM public.family_devices
  WHERE family_id = v_caller.family_id
    AND revoked_at IS NULL
    AND device_fp <> p_target_device_fp;

  RETURN json_build_object(
    'new_key_version', v_new_version,
    'survivors',       coalesce(v_survivors, '[]'::json)
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.revoke_caregiver_atomic(bytea, bytea) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.revoke_caregiver_atomic(bytea, bytea) FROM anon;
GRANT  EXECUTE ON FUNCTION public.revoke_caregiver_atomic(bytea, bytea) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) right_to_be_forgotten — require caller to be an active admin of the family
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.right_to_be_forgotten(p_family_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_audit_id uuid;
BEGIN
  -- Auth gate: caller must currently be an admin of the family being erased.
  -- service_role bypasses this gate (auth.uid() is NULL under service_role
  -- and the EXISTS check would always fail, so we explicitly allow that path
  -- via current_setting check).
  IF current_setting('role', true) <> 'service_role'
     AND NOT EXISTS (
       SELECT 1 FROM public.family_devices
       WHERE family_id    = p_family_id
         AND auth_user_id = auth.uid()
         AND role         = 'admin'
         AND revoked_at IS NULL
     ) THEN
    RAISE EXCEPTION 'forbidden: caller is not admin of family %', p_family_id
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.audit_events (family_id, event_type, event_data)
  VALUES (p_family_id, 'erasure_requested', jsonb_build_object('source', 'user_request'))
  RETURNING id INTO v_audit_id;

  DELETE FROM public.encrypted_snapshots       WHERE family_id = p_family_id;
  DELETE FROM public.encrypted_rows            WHERE family_id = p_family_id;
  DELETE FROM public.key_distribution          WHERE family_id = p_family_id;
  DELETE FROM public.invites                   WHERE family_id = p_family_id;
  DELETE FROM public.family_recovery_envelopes WHERE family_id = p_family_id;
  DELETE FROM public.recovery_attempts         WHERE family_id = p_family_id;
  DELETE FROM public.device_sync_cursors       WHERE family_id = p_family_id;
  DELETE FROM public.family_devices            WHERE family_id = p_family_id;
  DELETE FROM public.families                  WHERE id        = p_family_id;

  UPDATE public.audit_events
    SET event_data = event_data || '{"erased": true}'::jsonb
  WHERE id = v_audit_id;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.right_to_be_forgotten(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.right_to_be_forgotten(uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.right_to_be_forgotten(uuid) TO authenticated;
GRANT  EXECUTE ON FUNCTION public.right_to_be_forgotten(uuid) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) compact_family_versions — service_role only (maintenance / cron)
-- ─────────────────────────────────────────────────────────────────────────────
-- Function body is unchanged; only the grants are tightened.
REVOKE EXECUTE ON FUNCTION public.compact_family_versions(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.compact_family_versions(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.compact_family_versions(uuid) FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.compact_family_versions(uuid) TO service_role;

COMMIT;
