-- Critical security and correctness fixes for Plan C sync.
--
-- Fix 1: written_by_device bytea → text
--   The Dart client sends device_fp as a plain hex string (no \x prefix).
--   Keeping the column as bytea caused every push to fail with a type error.
--   Semantically, device_fp is a hex identifier, not raw binary data.
--
-- Fix 2: bootstrap_family_atomic auth_user_id overwrite guard
--   Migration 0013 allowed unconditional overwrite, opening an account-takeover
--   window: any caller who knows Device A's public key could re-bootstrap as
--   themselves and steal A's sync access. Now only NULL or same-user updates.
--
-- Fix 3: claim_invite_atomic failed_attempts increment restored
--   Migration 0011 rewrote the function but accidentally dropped the
--   failed_attempts increment that migration 0004 added. The brute-force
--   lockout check was present but dead code.

-- Fix 1: Change written_by_device from bytea to text.
ALTER TABLE public.encrypted_rows
  ALTER COLUMN written_by_device TYPE text
  USING encode(written_by_device, 'hex');

-- Fix 2: Secure bootstrap_family_atomic.
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
    -- Only update auth_user_id when it is NULL (first-time session heal) or
    -- already belongs to the same anonymous caller (idempotent re-bootstrap).
    -- An attacker knowing the pubkey cannot overwrite a bound device's session.
    UPDATE public.family_devices
      SET auth_user_id = auth.uid()
    WHERE device_fp = v_device_fp AND family_id = v_existing
      AND (auth_user_id IS NULL OR auth_user_id = auth.uid());
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

-- Fix 3: Restore failed_attempts increment in claim_invite_atomic.
CREATE OR REPLACE FUNCTION public.claim_invite_atomic(
  p_code_hash text,
  p_device_fp bytea,
  p_device_pub_key bytea
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invite  public.invites%rowtype;
  v_family  public.families%rowtype;
  v_kd      public.key_distribution%rowtype;
BEGIN
  SELECT * INTO v_invite FROM public.invites WHERE code_hash = p_code_hash FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION '404'; END IF;
  IF v_invite.failed_attempts >= 5 THEN RAISE EXCEPTION '410'; END IF;

  -- Expired or already consumed: count this attempt and refuse.
  IF v_invite.expires_at < now() OR v_invite.consumed_at IS NOT NULL THEN
    UPDATE public.invites
      SET failed_attempts = failed_attempts + 1
    WHERE code_hash = p_code_hash;
    RAISE EXCEPTION '410';
  END IF;

  SELECT * INTO v_family FROM public.families WHERE id = v_invite.family_id;

  -- Idempotent re-claim: device already in this family (re-install scenario).
  IF EXISTS (
    SELECT 1 FROM public.family_devices
    WHERE device_fp = p_device_fp AND family_id = v_invite.family_id
  ) THEN
    UPDATE public.family_devices
      SET auth_user_id = auth.uid()
    WHERE device_fp = p_device_fp AND family_id = v_invite.family_id
      AND (auth_user_id IS NULL OR auth_user_id = auth.uid());

    SELECT * INTO v_kd FROM public.key_distribution
    WHERE family_id = v_invite.family_id
      AND recipient_device_fp = p_device_fp
      AND key_version = v_family.current_key_version;

    RETURN json_build_object(
      'salt',        replace(encode(v_invite.salt,    'base64'), E'\n', ''),
      'wrapped_key', replace(encode(v_kd.wrapped_key, 'base64'), E'\n', ''),
      'family_id',   v_invite.family_id,
      'key_version', v_family.current_key_version
    );
  END IF;

  UPDATE public.invites
    SET consumed_at = now(), claim_device_fp = p_device_fp
  WHERE code_hash = p_code_hash;

  INSERT INTO public.family_devices
    (device_fp, family_id, device_pub_key, role, joined_at, key_version_at_join, auth_user_id)
  VALUES
    (p_device_fp, v_invite.family_id, p_device_pub_key, 'editor', now(),
     v_family.current_key_version, auth.uid())
  ON CONFLICT (device_fp) DO NOTHING;

  INSERT INTO public.key_distribution
    (family_id, recipient_device_fp, key_version, wrapped_key)
  VALUES
    (v_invite.family_id, p_device_fp, v_family.current_key_version, v_invite.wrapped_key)
  ON CONFLICT (family_id, recipient_device_fp, key_version) DO NOTHING;

  RETURN json_build_object(
    'salt',        replace(encode(v_invite.salt,        'base64'), E'\n', ''),
    'wrapped_key', replace(encode(v_invite.wrapped_key, 'base64'), E'\n', ''),
    'family_id',   v_invite.family_id,
    'key_version', v_family.current_key_version
  );
END;
$$;
