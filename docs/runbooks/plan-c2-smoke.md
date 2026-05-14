# Plan C-2 — 2-device manual smoke checklist

Pre-req: a real Supabase project (Cloud) and two Android emulators (or 1 emulator + 1 real device) with the debug APK installed.

## 1. Project setup

- Copy `.env.example` to `.env` and paste real `SUPABASE_URL` + `SUPABASE_ANON_KEY`.
- Apply migrations: `supabase link --project-ref <ref>` then `supabase db push`.
- Deploy Edge Functions: `supabase functions deploy claim_invite revoke_caregiver cleanup_tombstones`.
- Verify both Edge Functions show in Studio → Edge Functions → list.

## 2. Device A — admin

- Cold-launch the app.
- Complete onboarding (welcome → create baby).
- Log a feed: 4 oz bottle. Confirm row appears in local DB and in Supabase Studio → `encrypted_rows` (`ciphertext` should be binary, NOT readable text).
- In Studio SQL editor: `select pg_typeof(ciphertext), length(ciphertext) from encrypted_rows limit 1;` — expect type `bytea`, length > 28.

## 3. Device B — caregiver (manual bootstrap in C-2)

- Note: caregiver invite UI lands in Plan C-3. In C-2 use the debug CLI helper or manually insert a `family_devices` row + push `K_family` to secure storage.
- Verify sync pulls Device A's earlier feed within 5 seconds of foreground.

## 4. Revoke + rotation smoke

- On Device A, call `rotateRevokeAndFanOut` via debug menu (or test harness).
- Verify in Studio: Device B's `revoked_at` is set, `families.current_key_version` bumped.
- Verify Device B can no longer insert into `encrypted_rows` (RLS denies revoked device).
- Verify surviving devices received new `key_distribution` row.

## 5. Cleanup

- Check tombstone cleanup manually: set one `deleted_at` to 91 days ago in Studio, trigger `cleanup_tombstones` manually, verify row is hard-deleted.

## 6. iOS backup exclusion verify

- Install debug IPA on iPhone.
- Enable iCloud backup.
- Check Console: no `dreambook.db` in the iCloud drive backup manifest.
- Alternatively: use `idevicebackup2 info` to confirm the file is excluded.
