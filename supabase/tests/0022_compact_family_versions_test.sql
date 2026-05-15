-- supabase/tests/0022_compact_family_versions_test.sql
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(3);

-- 1. Function exists
SELECT has_function('public', 'compact_family_versions',
  ARRAY['uuid'],
  'function compact_family_versions(uuid) exists');

-- 2. Returns table type with deleted_count bigint
SELECT function_returns('public', 'compact_family_versions',
  ARRAY['uuid'],
  'record',
  'compact_family_versions returns a set of records (TABLE type)');

-- 3. Is SECURITY DEFINER
SELECT ok(
  (SELECT prosecdef FROM pg_proc
   WHERE proname = 'compact_family_versions'
     AND pronamespace = 'public'::regnamespace),
  'compact_family_versions is SECURITY DEFINER'
);

SELECT * FROM finish();
ROLLBACK;
