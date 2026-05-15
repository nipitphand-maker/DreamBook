-- supabase/tests/0018_audit_events_test.sql
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(9);

-- Fixtures
INSERT INTO auth.users (id, email) VALUES
  ('11111111-1111-1111-1111-111111111111', 'a@test');

INSERT INTO public.families (id, current_key_version)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 1);

INSERT INTO public.family_devices
  (device_fp, family_id, device_pub_key, role, key_version_at_join, auth_user_id)
VALUES
  (decode('aa11','hex'), 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '\x00','admin', 1, '11111111-1111-1111-1111-111111111111');

-- 1. Table exists
SELECT has_table('public', 'audit_events', 'table audit_events exists');

-- 2. Index exists
SELECT has_index('public', 'audit_events', 'audit_events_by_family',
  'index audit_events_by_family exists');

-- 3. RLS is enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class
   WHERE oid = 'public.audit_events'::regclass),
  'RLS is enabled on audit_events'
);

-- 4a. event_type CHECK includes 'invite_created'
SELECT lives_ok($$
  INSERT INTO public.audit_events (family_id, event_type)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'invite_created')
$$, 'event_type invite_created is valid');

-- 4b. event_type CHECK includes 'sync_background_started'
SELECT lives_ok($$
  INSERT INTO public.audit_events (family_id, event_type)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'sync_background_started')
$$, 'event_type sync_background_started is valid');

-- 4c. event_type CHECK includes 'realtime_reconnected'
SELECT lives_ok($$
  INSERT INTO public.audit_events (family_id, event_type)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'realtime_reconnected')
$$, 'event_type realtime_reconnected is valid');

-- 4d. Invalid event_type is rejected
SELECT throws_ok($$
  INSERT INTO public.audit_events (family_id, event_type)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'not_a_valid_event')
$$, '23514', NULL, 'invalid event_type rejected by CHECK');

-- 5. Attempt INSERT as authenticated → throws (INSERT restricted to service_role)
SET LOCAL role authenticated;
SET LOCAL "request.jwt.claim.sub" TO '11111111-1111-1111-1111-111111111111';
SELECT throws_ok($$
  INSERT INTO public.audit_events (family_id, event_type)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'invite_created')
$$, '42501', NULL, 'INSERT as authenticated blocked — restricted to service_role');

RESET role;

-- 6. family_id can be NULL (SET NULL on CASCADE DELETE)
SELECT col_is_null('public', 'audit_events', 'family_id',
  'family_id column is nullable (SET NULL on delete)');

SELECT * FROM finish();
ROLLBACK;
