-- Add auth_user_id to family_devices so RLS can use auth.uid() for row access.
-- device_fp (SHA-256 of pubkey, 16B) != uuid_send(auth.uid()) (16B UUID), so
-- all encrypted_rows SELECT/INSERT returned 500/recursion. Fix: link via auth_user_id.

ALTER TABLE public.family_devices
  ADD COLUMN IF NOT EXISTS auth_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;

-- Drop policies before dropping the function they depend on.
DROP POLICY IF EXISTS family_devices_select ON public.family_devices;
DROP POLICY IF EXISTS encrypted_rows_select ON public.encrypted_rows;
DROP POLICY IF EXISTS encrypted_rows_insert ON public.encrypted_rows;
DROP POLICY IF EXISTS encrypted_rows_update ON public.encrypted_rows;

DROP FUNCTION IF EXISTS public.current_device_family_ids();
DROP FUNCTION IF EXISTS public.current_user_family_ids();

CREATE OR REPLACE FUNCTION public.current_user_family_ids()
RETURNS SETOF uuid
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public
AS $$
  SELECT family_id FROM public.family_devices
  WHERE auth_user_id = auth.uid()
    AND revoked_at IS NULL;
$$;

CREATE POLICY family_devices_select ON public.family_devices
  FOR SELECT USING (family_id IN (SELECT public.current_user_family_ids()));

CREATE POLICY encrypted_rows_select ON public.encrypted_rows
  FOR SELECT USING (family_id IN (SELECT public.current_user_family_ids()));

CREATE POLICY encrypted_rows_insert ON public.encrypted_rows
  FOR INSERT WITH CHECK (family_id IN (SELECT public.current_user_family_ids()));

CREATE POLICY encrypted_rows_update ON public.encrypted_rows
  FOR UPDATE USING (family_id IN (SELECT public.current_user_family_ids()))
  WITH CHECK (family_id IN (SELECT public.current_user_family_ids()));

-- Update bootstrap_family_atomic to store auth.uid().
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
    UPDATE public.family_devices
      SET auth_user_id = auth.uid()
    WHERE device_fp = v_device_fp AND family_id = v_existing AND auth_user_id IS NULL;
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

-- Update claim_invite_atomic to store auth.uid().
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
  IF v_invite.expires_at < now() THEN RAISE EXCEPTION '410'; END IF;

  SELECT * INTO v_family FROM public.families WHERE id = v_invite.family_id;

  IF EXISTS (
    SELECT 1 FROM public.family_devices
    WHERE device_fp = p_device_fp AND family_id = v_invite.family_id
  ) THEN
    UPDATE public.family_devices
      SET auth_user_id = auth.uid()
    WHERE device_fp = p_device_fp AND family_id = v_invite.family_id AND auth_user_id IS NULL;

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

  IF v_invite.consumed_at IS NOT NULL THEN RAISE EXCEPTION '410'; END IF;

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
