-- supabase/migrations/0029_fix_revoke_atomic_trust_ef.sql
--
-- Migration 0027 added an `auth_user_id = auth.uid()` check inside
-- `revoke_caregiver_atomic`. That check ALWAYS fails in production because
-- the Edge Function `revoke_caregiver/index.ts` invokes the RPC via the
-- service_role admin client — and `auth.uid()` returns NULL under
-- service_role. Result: every legitimate admin revoke also failed 403
-- (only the UI hid the failure, deceiving the user into thinking revoke
-- succeeded — a separate UI bug to fix in `manage_devices_screen.dart`).
--
-- The Edge Function is the right place for the auth check:
--   1. It calls `userClient.auth.getUser()` to authenticate via JWT.
--   2. It selects `family_devices.device_fp` filtered by `auth_user_id = user.id`
--      using `userClient` (RLS-enforced).
--   3. It then passes the resolved `device_fp` to the RPC as `p_caller_device_fp`.
-- The RPC only needs to verify the caller's role is admin — auth is already
-- done at the EF boundary.

BEGIN;

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
  -- Auth gate is enforced by revoke_caregiver Edge Function (JWT + RLS).
  -- This RPC trusts the EF-resolved caller fp and verifies role only.
  SELECT * INTO v_caller
  FROM public.family_devices
  WHERE device_fp = p_caller_device_fp
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

COMMIT;
