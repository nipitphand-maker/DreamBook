-- supabase/tests/0019_recovery_tables_test.sql
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(9);

-- Fixtures
INSERT INTO auth.users (id, email) VALUES
  ('11111111-1111-1111-1111-111111111111', 'a@test');

INSERT INTO public.families (id, current_key_version)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 1);

-- 1a. family_recovery_envelopes exists
SELECT has_table('public', 'family_recovery_envelopes',
  'table family_recovery_envelopes exists');

-- 1b. recovery_attempts exists
SELECT has_table('public', 'recovery_attempts',
  'table recovery_attempts exists');

-- 1c. recovery_lookup exists
SELECT has_table('public', 'recovery_lookup',
  'table recovery_lookup exists');

-- 2a. family_recovery_envelopes has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class
   WHERE oid = 'public.family_recovery_envelopes'::regclass),
  'RLS is enabled on family_recovery_envelopes'
);

-- 2b. recovery_attempts has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class
   WHERE oid = 'public.recovery_attempts'::regclass),
  'RLS is enabled on recovery_attempts'
);

-- 2c. recovery_lookup has RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class
   WHERE oid = 'public.recovery_lookup'::regclass),
  'RLS is enabled on recovery_lookup'
);

-- 3a. family_recovery_envelopes grants SELECT to authenticated
SELECT ok(
  has_table_privilege('authenticated', 'public.family_recovery_envelopes', 'SELECT'),
  'authenticated has SELECT on family_recovery_envelopes'
);

-- 3b. recovery_attempts does NOT grant SELECT to authenticated
SELECT ok(
  NOT has_table_privilege('authenticated', 'public.recovery_attempts', 'SELECT'),
  'authenticated does NOT have SELECT on recovery_attempts'
);

-- 3c. recovery_lookup does NOT grant SELECT to authenticated
SELECT ok(
  NOT has_table_privilege('authenticated', 'public.recovery_lookup', 'SELECT'),
  'authenticated does NOT have SELECT on recovery_lookup'
);

SELECT * FROM finish();
ROLLBACK;
