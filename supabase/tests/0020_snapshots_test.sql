-- supabase/tests/0020_snapshots_test.sql
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(14);

-- Fixtures
INSERT INTO public.families (id, current_key_version)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 1);

-- 1. Table exists
SELECT has_table('public', 'encrypted_snapshots',
  'table encrypted_snapshots exists');

-- 1. Expected columns exist
SELECT has_column('public', 'encrypted_snapshots', 'id',
  'column id exists');
SELECT has_column('public', 'encrypted_snapshots', 'family_id',
  'column family_id exists');
SELECT has_column('public', 'encrypted_snapshots', 'version',
  'column version exists');
SELECT has_column('public', 'encrypted_snapshots', 'storage_path',
  'column storage_path exists');
SELECT has_column('public', 'encrypted_snapshots', 'wrapped_key',
  'column wrapped_key exists');
SELECT has_column('public', 'encrypted_snapshots', 'salt',
  'column salt exists');
SELECT has_column('public', 'encrypted_snapshots', 'payload_hash',
  'column payload_hash exists');
SELECT has_column('public', 'encrypted_snapshots', 'size_bytes',
  'column size_bytes exists');
SELECT has_column('public', 'encrypted_snapshots', 'created_at',
  'column created_at exists');
SELECT has_column('public', 'encrypted_snapshots', 'last_accessed_at',
  'column last_accessed_at exists');

-- 2. Index exists
SELECT has_index('public', 'encrypted_snapshots', 'encrypted_snapshots_by_family',
  'index encrypted_snapshots_by_family exists');

-- 3. UNIQUE constraint on (family_id, version)
SELECT throws_ok($$
  INSERT INTO public.encrypted_snapshots
    (family_id, version, storage_path, wrapped_key, salt, payload_hash, size_bytes)
  VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 1, 'path/a', '\x00', '\x00', '\x00', 100);
  INSERT INTO public.encrypted_snapshots
    (family_id, version, storage_path, wrapped_key, salt, payload_hash, size_bytes)
  VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 1, 'path/b', '\x00', '\x00', '\x00', 200);
$$, '23505', NULL, 'UNIQUE constraint on (family_id, version) blocks duplicates');

-- 4. RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class
   WHERE oid = 'public.encrypted_snapshots'::regclass),
  'RLS is enabled on encrypted_snapshots'
);

SELECT * FROM finish();
ROLLBACK;
