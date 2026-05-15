-- When a device re-bootstraps (same device_fp, family already exists),
-- always overwrite auth_user_id with the current auth.uid() — not only
-- when it is NULL. This lets a device that previously bootstrapped without
-- a valid session (e.g. anonymous sign-ins disabled at the time) fix its
-- auth_user_id by re-opening the Share screen.
CREATE OR REPLACE FUNCTION public.bootstrap_family_atomic(
  p_device_fp_hex text,
  p_device_pub_key bytea
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_device_fp bytea;
  v_family_id uuid;
  v_existing  uuid;
BEGIN
  v_device_fp := decode(p_device_fp_hex, 'hex');

  SELECT family_id INTO v_existing
  FROM public.family_devices
  WHERE device_fp = v_device_fp AND role = 'admin' AND revoked_at IS NULL
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    -- Always refresh auth_user_id on re-bootstrap so a device that first
    -- ran without a valid session can self-heal by calling bootstrap again.
    UPDATE public.family_devices
      SET auth_user_id = auth.uid()
    WHERE device_fp = v_device_fp AND family_id = v_existing;
    RETURN json_build_object('family_id', v_existing::text, 'device_fp', p_device_fp_hex);
  END IF;

  INSERT INTO public.families DEFAULT VALUES RETURNING id INTO v_family_id;

  INSERT INTO public.family_devices
    (device_fp, family_id, device_pub_key, role, key_version_at_join, auth_user_id)
  VALUES
    (v_device_fp, v_family_id, p_device_pub_key, 'admin', 1, auth.uid());

  RETURN json_build_object('family_id', v_family_id::text, 'device_fp', p_device_fp_hex);
END;
$$;
