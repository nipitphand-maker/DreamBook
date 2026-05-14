# DreamBook Supabase setup

## Local development
1. `brew install supabase/tap/supabase` (one-time).
2. `supabase start` — boots Postgres + Auth + Storage + Studio on localhost:54321.
3. `supabase db reset` — applies migrations from `supabase/migrations/`.
4. Open `http://localhost:54323` for the Studio UI.

## Cloud project (production)
1. Create project in region `ap-southeast-1` (Singapore).
2. Copy project URL and `anon` key into `.env`.
3. `supabase link --project-ref <ref>` then `supabase db push` to apply migrations.
4. Deploy Edge Functions: `supabase functions deploy claim_invite revoke_caregiver cleanup_tombstones`.

## Schema verification
After applying, the `public` schema should contain:
- families
- family_devices
- encrypted_rows
- invites
- key_distribution

## RLS smoke checklist

Run against local Supabase (`psql postgres://postgres:postgres@localhost:54322/postgres`):

```sql
-- Test 1: unauthenticated insert rejected
set role anon;
insert into encrypted_rows
  (family_id, table_name, record_id, version, key_version,
   ciphertext, aad_hash, written_by_device)
values
  ('00000000-0000-0000-0000-000000000000', 'feed', 'x', 1, 1,
   '\x00', '\x00', '\x00');
-- Expected: ERROR — new row violates row-level security policy
```

- Device with `revoked_at IS NOT NULL` fails encrypted_rows insert (fd.revoked_at is null check)
- Device reads only its own `key_distribution` rows (recipient_device_fp = decode(auth.uid()::text, 'hex'))
