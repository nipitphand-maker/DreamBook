-- Drop the old single-param bootstrap_family_atomic that PostgREST may route to
-- (it pre-dates the auth_user_id fix and has no auth_user_id storage).
DROP FUNCTION IF EXISTS public.bootstrap_family_atomic(bytea);

-- Back-fill auth_user_id for any admin rows that were bootstrapped while
-- the old function was still being used (auth.uid() returned NULL).
-- The anonymous user sign-in happens just before bootstrap, so we can
-- match by finding the most recently created anonymous user per family.
UPDATE public.family_devices fd
SET auth_user_id = (
  SELECT u.id FROM auth.users u
  WHERE u.is_anonymous = true
    AND u.created_at BETWEEN fd.joined_at - INTERVAL '2 minutes'
                          AND fd.joined_at + INTERVAL '2 minutes'
  ORDER BY u.created_at
  LIMIT 1
)
WHERE fd.role = 'admin'
  AND fd.auth_user_id IS NULL
  AND fd.revoked_at IS NULL;
