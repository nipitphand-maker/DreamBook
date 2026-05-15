-- supabase/tests/0017_rls_reharden_test.sql
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(10);

-- Fixtures: two auth users, two devices, one family.
INSERT INTO auth.users (id, email) VALUES
  ('11111111-1111-1111-1111-111111111111', 'a@test'),
  ('22222222-2222-2222-2222-222222222222', 'b@test');

INSERT INTO public.families (id, current_key_version)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 1);

INSERT INTO public.family_devices
  (device_fp, family_id, device_pub_key, role, key_version_at_join, auth_user_id)
VALUES
  (decode('aa11','hex'), 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '\x00','admin', 1, '11111111-1111-1111-1111-111111111111'),
  (decode('bb22','hex'), 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '\x00','editor',1, '22222222-2222-2222-2222-222222222222');

-- 1. Structure assertions: new columns exist
SELECT has_column('public','families','tombstone_retention_days');
SELECT has_column('public','families','last_active_at');
SELECT col_default_is('public','families','tombstone_retention_days','90');

-- 2. Indexes exist
SELECT has_index('public','family_devices','family_devices_auth_user_id_idx');
SELECT has_index('public','family_devices','family_devices_device_fp_active_idx');

-- 3. Grants
SELECT ok(has_table_privilege('authenticated','public.families','SELECT'),
          'authenticated has SELECT on families');
SELECT ok(has_table_privilege('authenticated','public.family_devices','SELECT'),
          'authenticated has SELECT on family_devices');

-- 4. Spoofed written_by_device REJECTED.
SET LOCAL role authenticated;
SET LOCAL "request.jwt.claim.sub" TO '11111111-1111-1111-1111-111111111111';
SELECT throws_ok($$
  INSERT INTO public.encrypted_rows
    (family_id, table_name, record_id, version, key_version,
     ciphertext, aad_hash, written_by_device)
  VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','feed','r1',1,1,
     '\x00','\x00','bb22')
$$, '42501', NULL, 'spoofed device_fp blocked by RLS WITH CHECK');

-- 5. Correct written_by_device + key_version ACCEPTED.
SELECT lives_ok($$
  INSERT INTO public.encrypted_rows
    (family_id, table_name, record_id, version, key_version,
     ciphertext, aad_hash, written_by_device)
  VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','feed','r1',1,1,
     '\x00','\x00','aa11')
$$, 'own device_fp accepted');

-- 6. Stale key_version REJECTED (proves the key_version predicate fires).
SELECT throws_ok($$
  INSERT INTO public.encrypted_rows
    (family_id, table_name, record_id, version, key_version,
     ciphertext, aad_hash, written_by_device)
  VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','feed','r2',1,99,
     '\x00','\x00','aa11')
$$, '42501', NULL, 'stale key_version blocked by RLS WITH CHECK');

SELECT * FROM finish();
ROLLBACK;
