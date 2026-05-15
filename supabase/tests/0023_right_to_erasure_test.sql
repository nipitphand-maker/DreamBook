-- supabase/tests/0023_right_to_erasure_test.sql
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(7);

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

-- 4. Behavioral: erasure actually deletes data
INSERT INTO public.families (id, current_key_version)
  VALUES ('cccccccc-cccc-cccc-cccc-cccccccccccc', 1);
INSERT INTO public.encrypted_rows
  (family_id, table_name, record_id, version, key_version, ciphertext, aad_hash, written_by_device)
VALUES
  ('cccccccc-cccc-cccc-cccc-cccccccccccc','feed','r-erase',1,1,'\x00','\x00','aa11');

SELECT lives_ok($$
  SELECT public.right_to_be_forgotten('cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid)
$$, 'right_to_be_forgotten runs without error');

SELECT is(
  (SELECT count(*)::int FROM public.encrypted_rows
   WHERE family_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
  0,
  'encrypted_rows deleted after erasure'
);

SELECT is(
  (SELECT count(*)::int FROM public.families
   WHERE id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
  0,
  'families row deleted after erasure'
);

SELECT is(
  (SELECT count(*)::int FROM public.audit_events
   WHERE (event_data->>'erased')::boolean = true),
  1,
  'audit_events erased=true row present'
);

SELECT * FROM finish();
ROLLBACK;
