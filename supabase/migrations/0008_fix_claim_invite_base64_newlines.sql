-- 0008: Fix BUG-CLAIM-1 — PostgreSQL encode(bytea,'base64') inserts \n every 76
-- chars (MIME convention). Dart's base64Decode() is strict RFC 4648 and rejects
-- embedded newlines, producing:
--   FormatException: Invalid character (at character 77)
-- The wrapped_key is 60 bytes → 80 base64 chars → crosses the 76-char boundary.
-- Fix: strip \n from both 'salt' and 'wrapped_key' in the JSON response.
-- Adding SET search_path = public for defence-in-depth (matches other functions).

CREATE OR REPLACE FUNCTION public.claim_invite_atomic(
  p_code_hash text,
  p_device_fp bytea,
  p_device_pub_key bytea
) returns json
language plpgsql
security definer
SET search_path = public
as $$
declare
  v_invite public.invites%rowtype;
  v_family public.families%rowtype;
begin
  select * into v_invite from public.invites where code_hash = p_code_hash for update;
  if not found then raise exception '404'; end if;
  if v_invite.failed_attempts >= 5 then raise exception '410'; end if;
  if v_invite.expires_at < now() then raise exception '410'; end if;
  if v_invite.consumed_at is not null then raise exception '410'; end if;

  update public.invites
    set consumed_at = now(), claim_device_fp = p_device_fp
    where code_hash = p_code_hash;

  select * into v_family from public.families where id = v_invite.family_id;

  insert into public.family_devices
    (device_fp, family_id, device_pub_key, role, joined_at, key_version_at_join)
    values (p_device_fp, v_invite.family_id, p_device_pub_key,
            'editor', now(), v_family.current_key_version);

  insert into public.key_distribution
    (family_id, recipient_device_fp, key_version, wrapped_key)
    values (v_invite.family_id, p_device_fp, v_family.current_key_version,
            v_invite.wrapped_key);

  -- BUGFIX: replace() strips the MIME \n that Postgres inserts every 76 chars.
  return json_build_object(
    'salt',        replace(encode(v_invite.salt,        'base64'), E'\n', ''),
    'wrapped_key', replace(encode(v_invite.wrapped_key, 'base64'), E'\n', ''),
    'family_id',   v_invite.family_id,
    'key_version', v_family.current_key_version
  );
end;
$$;
