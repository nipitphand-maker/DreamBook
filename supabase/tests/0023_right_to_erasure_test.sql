-- supabase/tests/0023_right_to_erasure_test.sql
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(3);

-- 1. Function exists
SELECT has_function('public', 'right_to_be_forgotten',
  ARRAY['uuid'],
  'function right_to_be_forgotten(uuid) exists');

-- 2. Is SECURITY DEFINER
SELECT ok(
  (SELECT prosecdef FROM pg_proc
   WHERE proname = 'right_to_be_forgotten'
     AND pronamespace = 'public'::regnamespace),
  'right_to_be_forgotten is SECURITY DEFINER'
);

-- 3. Returns void
SELECT function_returns('public', 'right_to_be_forgotten',
  ARRAY['uuid'],
  'void',
  'right_to_be_forgotten returns void');

SELECT * FROM finish();
ROLLBACK;
