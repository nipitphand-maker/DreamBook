-- Add IP-level rate-limit support and retention index to recovery_attempts.
--
-- The existing auth_user_id rate limit (5 failures / hour) stops a single Supabase
-- anonymous user from brute-forcing recovery hashes, but an attacker can create
-- multiple anonymous sessions to bypass it. A per-IP limit blocks that path.
--
-- Changes:
--   1. Add client_ip INET column (nullable — populated by Edge Functions via
--      CF-Connecting-IP / X-Forwarded-For header).
--   2. Index (client_ip, attempted_at) for efficient per-IP rate-limit queries.
--   3. Index (attempted_at) for retention queries (periodic purge of old attempts).

ALTER TABLE public.recovery_attempts
  ADD COLUMN IF NOT EXISTS client_ip INET;

CREATE INDEX IF NOT EXISTS recovery_attempts_client_ip_idx
  ON public.recovery_attempts (client_ip, attempted_at DESC)
  WHERE client_ip IS NOT NULL;

CREATE INDEX IF NOT EXISTS recovery_attempts_attempted_at_idx
  ON public.recovery_attempts (attempted_at DESC);
