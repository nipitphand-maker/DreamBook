-- Allow recovery_attempts to record pre-family-resolution failures.
-- Before this, a 404 (lookup_hash not found) could not be logged because
-- family_id was NOT NULL — the rate-limit insert would fail and the
-- brute-force attempt went unrecorded.
ALTER TABLE public.recovery_attempts
  ALTER COLUMN family_id DROP NOT NULL;

ALTER TABLE public.recovery_attempts
  ADD COLUMN IF NOT EXISTS auth_user_id uuid;

CREATE INDEX IF NOT EXISTS recovery_attempts_auth_user_id_attempted_at_idx
  ON public.recovery_attempts (auth_user_id, attempted_at DESC);
