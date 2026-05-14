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

  return json_build_object(
    'salt', encode(v_invite.salt, 'base64'),
    'wrapped_key', encode(v_invite.wrapped_key, 'base64'),
    'family_id', v_invite.family_id,
    'key_version', v_family.current_key_version
  );
end;
$$;

create or replace function public.revoke_caregiver_atomic(
  p_caller_device_fp bytea,
  p_target_device_fp bytea
) returns json
language plpgsql
security definer
as $$
declare
  v_caller public.family_devices%rowtype;
  v_target public.family_devices%rowtype;
  v_new_version int;
  v_survivors json;
begin
  select * into v_caller from public.family_devices where device_fp = p_caller_device_fp;
  if not found or v_caller.role <> 'admin' or v_caller.revoked_at is not null then
    raise exception '403';
  end if;
  select * into v_target from public.family_devices where device_fp = p_target_device_fp;
  if not found or v_target.family_id <> v_caller.family_id then
    raise exception '404';
  end if;
  if v_target.device_fp = v_caller.device_fp then
    raise exception '409';
  end if;

  update public.family_devices
    set revoked_at = now(), wipe_requested_at = now()
    where device_fp = p_target_device_fp;

  update public.families
    set current_key_version = current_key_version + 1
    where id = v_caller.family_id
    returning current_key_version into v_new_version;

  select json_agg(json_build_object(
    'device_fp', encode(device_fp, 'base64'),
    'device_pub_key', encode(device_pub_key, 'base64')
  )) into v_survivors
  from public.family_devices
  where family_id = v_caller.family_id
    and revoked_at is null
    and device_fp <> p_target_device_fp;

  return json_build_object(
    'new_key_version', v_new_version,
    'survivors', coalesce(v_survivors, '[]'::json)
  );
end;
$$;
