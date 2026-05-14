-- DreamBook Plan C-2 — Row-Level Security policies.
-- Auth model: anonymous Supabase auth gives each device an auth.uid().
-- That uid is mirrored to family_devices.device_fp at handshake time.

-- encrypted_rows: write only by active editors/admins of the family.
create policy encrypted_rows_insert on public.encrypted_rows
  for insert with check (
    exists (
      select 1 from public.family_devices fd
      where fd.family_id = encrypted_rows.family_id
        and fd.device_fp = decode(auth.uid()::text, 'hex')
        and fd.revoked_at is null
        and fd.role in ('editor', 'admin')
    )
    and encrypted_rows.key_version =
        (select current_key_version from public.families where id = encrypted_rows.family_id)
    and encrypted_rows.written_by_device = decode(auth.uid()::text, 'hex')
  );

create policy encrypted_rows_update on public.encrypted_rows
  for update using (
    exists (
      select 1 from public.family_devices fd
      where fd.family_id = encrypted_rows.family_id
        and fd.device_fp = decode(auth.uid()::text, 'hex')
        and fd.revoked_at is null
        and fd.role in ('editor', 'admin')
    )
  );

create policy encrypted_rows_select on public.encrypted_rows
  for select using (
    exists (
      select 1 from public.family_devices fd
      where fd.family_id = encrypted_rows.family_id
        and fd.device_fp = decode(auth.uid()::text, 'hex')
        and fd.revoked_at is null
    )
  );

-- key_distribution: a device can read only its own row.
create policy key_distribution_select_own on public.key_distribution
  for select using (
    recipient_device_fp = decode(auth.uid()::text, 'hex')
  );

-- key_distribution: only admin can fan out keys.
create policy key_distribution_insert_admin on public.key_distribution
  for insert with check (
    exists (
      select 1 from public.family_devices fd
      where fd.family_id = key_distribution.family_id
        and fd.device_fp = decode(auth.uid()::text, 'hex')
        and fd.role = 'admin'
        and fd.revoked_at is null
    )
  );

-- family_devices: read by members of the same family.
create policy family_devices_select on public.family_devices
  for select using (
    exists (
      select 1 from public.family_devices fd2
      where fd2.family_id = family_devices.family_id
        and fd2.device_fp = decode(auth.uid()::text, 'hex')
        and fd2.revoked_at is null
    )
  );

-- family_devices: writes are denied except through SECURITY DEFINER functions.
-- (No policies = denied for anon role.)

-- invites: writes are denied to anon entirely; reads denied.
-- Only Edge Functions with service-role bypass touch this table.
