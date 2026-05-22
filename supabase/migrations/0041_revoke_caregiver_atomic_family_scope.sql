-- revoke_caregiver_atomic: add p_family_id parameter to scope the caller
-- device lookup to the correct family.
--
-- After migration 0036 allows a device to appear in multiple families,
-- the previous query:
--   SELECT * INTO v_caller FROM family_devices
--   WHERE device_fp = p_caller_device_fp AND revoked_at IS NULL
-- can match multiple rows (same device_fp in multiple families). In plpgsql,
-- SELECT INTO with multiple rows silently takes the first row in physical order,
-- which is non-deterministic. If the caller is admin in family A but editor in
-- family B, the function could return 403 incorrectly.
--
-- Fix: accept p_family_id and scope the caller lookup by (device_fp, family_id).
-- The revoke_caregiver EF already has family_id in the request body (added in
-- the B8 hardening pass) and is updated here to pass it to the RPC.

BEGIN;

CREATE OR REPLACE FUNCTION public.revoke_caregiver_atomic(
  p_caller_device_fp bytea,
  p_target_device_fp bytea,
  p_family_id        uuid DEFAULT NULL
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_caller      public.family_devices%rowtype;
  v_target      public.family_devices%rowtype;
  v_new_version int;
  v_survivors   json;
BEGIN
  -- Auth gate is enforced by the Edge Function (JWT + RLS lookup).
  -- Scope by family_id when provided so multi-family devices resolve correctly.
  IF p_family_id IS NOT NULL THEN
    SELECT * INTO v_caller
    FROM public.family_devices
    WHERE device_fp = p_caller_device_fp
      AND family_id = p_family_id
      AND revoked_at IS NULL;
  ELSE
    -- Legacy path (p_family_id not yet supplied by older EF versions).
    SELECT * INTO v_caller
    FROM public.family_devices
    WHERE device_fp = p_caller_device_fp
      AND revoked_at IS NULL
    LIMIT 1;
  END IF;

  IF NOT FOUND OR v_caller.role <> 'admin' THEN
    RAISE EXCEPTION '403' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_target
  FROM public.family_devices
  WHERE device_fp = p_target_device_fp
    AND family_id = v_caller.family_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION '404' USING ERRCODE = 'P0002';
  END IF;
  IF v_target.device_fp = v_caller.device_fp THEN
    RAISE EXCEPTION '409' USING ERRCODE = '22023';
  END IF;

  UPDATE public.family_devices
    SET revoked_at = now(), wipe_requested_at = now()
  WHERE device_fp = p_target_device_fp
    AND family_id = v_caller.family_id;

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
