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
- Unauthenticated insert into `encrypted_rows` must fail with RLS error
- Device with `revoked_at IS NOT NULL` must not be able to insert rows
- Device can only read `key_distribution` rows where `recipient_device_fp` matches its own fingerprint
