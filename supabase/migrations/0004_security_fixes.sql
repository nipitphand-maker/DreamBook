-- Security fix: increment failed_attempts when a valid-but-exhausted/consumed
-- invite is attempted. The previous version checked the counter but never
-- incremented it, making the brute-force lockout dead code. (SEC-001)

create or replace function public.claim_invite_atomic(
  p_code_hash text,
  p_device_fp bytea,
  p_device_pub_key bytea
) returns json
language plpgsql
security definer
as $$
declare
  v_invite public.invites%rowtype;
  v_family public.families%rowtype;
begin
  select * into v_invite from public.invites where code_hash = p_code_hash for update;
  if not found then raise exception '404'; end if;

  -- Hard lockout: 5 failed attempts and the invite is permanently blocked.
  if v_invite.failed_attempts >= 5 then raise exception '410'; end if;

  -- Expired or already consumed: count this attempt and refuse.
  if v_invite.expires_at < now() or v_invite.consumed_at is not null then
    update public.invites
      set failed_attempts = failed_attempts + 1
      where code_hash = p_code_hash;
    raise exception '410';
  end if;

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

  return json_build_object(
    'salt', encode(v_invite.salt, 'base64'),
    'wrapped_key', encode(v_invite.wrapped_key, 'base64'),
    'family_id', v_invite.family_id,
    'key_version', v_family.current_key_version
  );
end;
$$;
