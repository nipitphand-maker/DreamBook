-- Migration 0015: distinguish brute-force lockout (429) from expired/consumed
-- invite codes (410) in claim_invite_atomic. The Edge Function and Flutter
-- client already handle 429 separately — this is the missing DB-side fix.

CREATE OR REPLACE FUNCTION public.claim_invite_atomic(
  p_code_hash text,
  p_device_fp bytea,
  p_device_pub_key bytea
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invite  public.invites%rowtype;
  v_family  public.families%rowtype;
  v_kd      public.key_distribution%rowtype;
BEGIN
  SELECT * INTO v_invite FROM public.invites WHERE code_hash = p_code_hash FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION '404'; END IF;
  IF v_invite.failed_attempts >= 5 THEN RAISE EXCEPTION '429'; END IF;

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
