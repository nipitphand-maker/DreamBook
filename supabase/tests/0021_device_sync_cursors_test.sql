-- supabase/tests/0021_device_sync_cursors_test.sql
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(9);

-- Fixtures
INSERT INTO public.families (id, current_key_version)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 1);

INSERT INTO public.family_devices
  (device_fp, family_id, device_pub_key, role, key_version_at_join)
VALUES
  (decode('aa11','hex'), 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '\x00', 'admin', 1);

-- 1. Table exists
SELECT has_table('public', 'device_sync_cursors',
  'table device_sync_cursors exists');

-- 1. Expected columns exist
SELECT has_column('public', 'device_sync_cursors', 'family_id',
  'column family_id exists');
SELECT has_column('public', 'device_sync_cursors', 'device_fp',
  'column device_fp exists');
SELECT has_column('public', 'device_sync_cursors', 'last_pulled_at',
  'column last_pulled_at exists');
SELECT has_column('public', 'device_sync_cursors', 'last_pulled_version_max',
  'column last_pulled_version_max exists');
SELECT has_column('public', 'device_sync_cursors', 'updated_at',
  'column updated_at exists');

-- 2. PK is (family_id, device_fp)
SELECT col_is_pk('public', 'device_sync_cursors',
  ARRAY['family_id', 'device_fp'],
  'primary key is (family_id, device_fp)');

-- 3. RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class
   WHERE oid = 'public.device_sync_cursors'::regclass),
  'RLS is enabled on device_sync_cursors'
);

-- 3. Authenticated has expected grants
SELECT ok(
  has_table_privilege('authenticated', 'public.device_sync_cursors', 'SELECT'),
  'authenticated has SELECT on device_sync_cursors'
);

SELECT * FROM finish();
ROLLBACK;
