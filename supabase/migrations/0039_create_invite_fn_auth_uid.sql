-- create_invite_fn: bind device lookup to auth.uid() so a caller cannot
-- forge an admin's device_fp from another family.
--
-- The previous version only checked (device_fp, family_id), which means any
-- authenticated user who learns an admin's hex fp could create invites in
-- that family by passing the known fp to the EF. Adding auth_user_id = auth.uid()
-- ensures the device row must also belong to the calling JWT's identity.

BEGIN;

-- The invite creation function tracks which device generated the invite.
-- Add the column if it was not already present (idempotent).
ALTER TABLE public.invites
  ADD COLUMN IF NOT EXISTS created_by_device_fp bytea;

CREATE OR REPLACE FUNCTION public.create_invite_fn(
  p_family_id     uuid,
  p_code_hash     text,
  p_salt          bytea,
  p_wrapped_key   bytea,
  p_device_fp_hex text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_device_fp  bytea;
  v_role       text;
  v_revoked    timestamptz;
  v_invite_id  uuid;
  v_expires_at timestamptz;
BEGIN
  v_device_fp := decode(p_device_fp_hex, 'hex');

  -- Auth gate: device row must match the calling JWT's auth.uid() so a
  -- caller cannot forge a known admin's fp from a different identity.
  SELECT role, revoked_at INTO v_role, v_revoked
  FROM public.family_devices
  WHERE device_fp    = v_device_fp
    AND family_id    = p_family_id
    AND auth_user_id = auth.uid()
  LIMIT 1;

  IF v_role IS NULL OR v_role <> 'admin' OR v_revoked IS NOT NULL THEN
    RAISE EXCEPTION 'Forbidden: not an active admin (403)';
  END IF;

  -- Server-enforced 1-hour TTL (SEC-002).
  v_expires_at := now() + INTERVAL '1 hour';

  INSERT INTO public.invites
    (family_id, code_hash, salt, wrapped_key, created_by_device_fp, expires_at)
  VALUES
    (p_family_id, p_code_hash, p_salt, p_wrapped_key, v_device_fp, v_expires_at)
  RETURNING id INTO v_invite_id;

  RETURN json_build_object('invite_id', v_invite_id::text, 'expires_at', v_expires_at);
END;
$$;

COMMIT;
