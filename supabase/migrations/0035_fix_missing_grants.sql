-- Fix two missing table-level GRANTs discovered during security audit:
--
-- 1. audit_events SELECT was never granted to authenticated despite the RLS
--    audit_events_select policy existing since migration 0018.
--    Without this, authenticated clients receive an empty result set instead
--    of a permission-error, making audit history queries silently useless.
--
-- 2. recovery_attempts UPDATE was never granted to service_role (only SELECT
--    and INSERT were granted in 0019). claim_recovery and restore_snapshot
--    both mark attempt success=true via an UPDATE — those silently failed,
--    leaving every attempt recorded as a failure even on success, which
--    corrupted the rate-limit counter.

GRANT SELECT ON public.audit_events TO authenticated;
GRANT UPDATE ON public.recovery_attempts TO service_role;
