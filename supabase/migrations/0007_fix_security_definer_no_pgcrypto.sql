-- 0007: Rewrite SECURITY DEFINER RPCs to receive pre-computed device_fp from
-- the Edge Function (SHA-256 computed via WebCrypto), removing the pgcrypto
-- dependency that broke because pgcrypto lives in the 'extensions' schema,
-- not 'public'.

-- bootstrap_family_atomic: caller passes pre-computed fp (hex) + raw pub key.
CREATE OR REPLACE FUNCTION public.bootstrap_family_atomic(
  p_device_fp_hex  TEXT,
  p_device_pub_key BYTEA
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_device_fp  BYTEA;
  v_family_id  UUID;
  v_existing   UUID;
BEGIN
  v_device_fp := decode(p_device_fp_hex, 'hex');

  SELECT family_id INTO v_existing
  FROM public.family_devices
  WHERE device_fp = v_device_fp
    AND role = 'admin'
    AND revoked_at IS NULL
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    RETURN json_build_object(
      'family_id', v_existing::TEXT,
      'device_fp', p_device_fp_hex
    );
  END IF;

  INSERT INTO public.families DEFAULT VALUES
  RETURNING id INTO v_family_id;

  INSERT INTO public.family_devices (device_fp, family_id, device_pub_key, role, key_version_at_join)
  VALUES (v_device_fp, v_family_id, p_device_pub_key, 'admin', 1);

  RETURN json_build_object(
    'family_id', v_family_id::TEXT,
    'device_fp', p_device_fp_hex
  );
END;
$$;

-- create_invite_fn: caller passes pre-computed fp (hex) instead of raw pub key.
CREATE OR REPLACE FUNCTION public.create_invite_fn(
  p_family_id     UUID,
  p_code_hash     TEXT,
  p_salt          BYTEA,
  p_wrapped_key   BYTEA,
  p_device_fp_hex TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_device_fp  BYTEA;
  v_role       TEXT;
  v_revoked    TIMESTAMPTZ;
BEGIN
  v_device_fp := decode(p_device_fp_hex, 'hex');

  SELECT role, revoked_at INTO v_role, v_revoked
  FROM public.family_devices
  WHERE device_fp = v_device_fp
    AND family_id = p_family_id
  LIMIT 1;

  IF v_role IS NULL OR v_role <> 'admin' OR v_revoked IS NOT NULL THEN
    RAISE EXCEPTION 'Forbidden: not an active admin (403)';
  END IF;

  -- Server-enforced 1-hour TTL (SEC-002).
  INSERT INTO public.invites (code_hash, family_id, salt, wrapped_key, expires_at)
  VALUES (p_code_hash, p_family_id, p_salt, p_wrapped_key, NOW() + INTERVAL '1 hour');

  RETURN json_build_object('ok', TRUE);
END;
$$;

-- Re-grant to anon (covers the new signatures).
GRANT EXECUTE ON FUNCTION public.bootstrap_family_atomic(TEXT, BYTEA) TO anon;
GRANT EXECUTE ON FUNCTION public.create_invite_fn(UUID, TEXT, BYTEA, BYTEA, TEXT) TO anon;
