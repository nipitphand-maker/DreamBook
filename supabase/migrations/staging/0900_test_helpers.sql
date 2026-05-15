-- STAGING ONLY — must never be applied to production.
-- CI rule (DV-3): files under supabase/migrations/staging/ excluded from prod migration list.
CREATE OR REPLACE FUNCTION public.test_only_age_recovery_attempts(
  p_family_id uuid,
  p_age interval
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF current_setting('app.test_mode', true) IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'test_only_* helpers may not be called outside test_mode';
  END IF;
  UPDATE public.recovery_attempts
  SET attempted_at = attempted_at - p_age
  WHERE family_id = p_family_id;
END;
$$;
