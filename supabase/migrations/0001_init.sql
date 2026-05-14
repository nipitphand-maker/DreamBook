-- DreamBook Plan C-2 — encrypted backend schema.
-- All data tables hold ciphertext only; plaintext never leaves the device.

create extension if not exists "uuid-ossp";

create table public.families (
  id uuid primary key default uuid_generate_v4(),
  current_key_version int not null default 1,
  created_at timestamptz not null default now()
);

create table public.family_devices (
  device_fp bytea primary key,
  family_id uuid not null references public.families(id) on delete cascade,
  device_pub_key bytea not null,
  role text not null check (role in ('admin', 'editor', 'readonly')),
  joined_at timestamptz not null default now(),
  revoked_at timestamptz,
  wipe_requested_at timestamptz,
  wipe_acked_at timestamptz,
  key_version_at_join int not null
);

create index family_devices_by_family on public.family_devices (family_id);
create index family_devices_revoked on public.family_devices (family_id, revoked_at) where revoked_at is not null;

create table public.encrypted_rows (
  id uuid primary key default uuid_generate_v4(),
  family_id uuid not null references public.families(id) on delete cascade,
  table_name text not null,
  record_id text not null,
  version int not null,
  key_version int not null,
  ciphertext bytea not null,
  aad_hash bytea not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  written_by_device bytea not null,
  unique (family_id, table_name, record_id, version)
);

create index encrypted_rows_by_updated_at on public.encrypted_rows (family_id, updated_at);
create index encrypted_rows_tombstones on public.encrypted_rows (deleted_at) where deleted_at is not null;

create table public.invites (
  code_hash text primary key,
  family_id uuid not null references public.families(id) on delete cascade,
  salt bytea not null,
  wrapped_key bytea not null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  claim_device_fp bytea,
  failed_attempts int not null default 0
);

create index invites_active on public.invites (expires_at) where consumed_at is null;

create table public.key_distribution (
  family_id uuid not null references public.families(id) on delete cascade,
  recipient_device_fp bytea not null references public.family_devices(device_fp) on delete cascade,
  key_version int not null,
  wrapped_key bytea not null,
  delivered_at timestamptz not null default now(),
  primary key (family_id, recipient_device_fp, key_version)
);

create index key_distribution_by_device on public.key_distribution (recipient_device_fp, family_id, key_version);

alter table public.families enable row level security;
alter table public.family_devices enable row level security;
alter table public.encrypted_rows enable row level security;
alter table public.invites enable row level security;
alter table public.key_distribution enable row level security;
