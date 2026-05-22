-- compact_family_versions was created in migration 0022 without
-- SET search_path = public, making it vulnerable to search_path injection.
-- All other SECURITY DEFINER functions in this codebase already carry the
-- SET search_path = public guard. This migration adds it by recreating the
-- function body unchanged except for the secure search_path clause.

BEGIN;

CREATE OR REPLACE FUNCTION public.compact_family_versions(p_family_id uuid)
RETURNS TABLE(deleted_count bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_min_cursor bigint;
  v_stale_device_count int;
BEGIN
  -- SSI-2: skip if any active device has not pulled in 7 days.
  SELECT COUNT(*) INTO v_stale_device_count
  FROM public.family_devices fd
  LEFT JOIN public.device_sync_cursors dsc
    ON dsc.family_id = fd.family_id AND dsc.device_fp = fd.device_fp
  WHERE fd.family_id = p_family_id
    AND fd.revoked_at IS NULL
    AND (dsc.last_pulled_at IS NULL OR dsc.last_pulled_at < now() - INTERVAL '7 days');
  IF v_stale_device_count > 0 THEN
    RETURN QUERY SELECT 0::bigint;
    RETURN;
  END IF;

  SELECT COALESCE(MIN(last_pulled_version_max), 0) INTO v_min_cursor
  FROM public.device_sync_cursors dsc
  JOIN public.family_devices fd ON fd.family_id = dsc.family_id AND fd.device_fp = dsc.device_fp
  WHERE dsc.family_id = p_family_id AND fd.revoked_at IS NULL;

  RETURN QUERY
  WITH latest AS (
    SELECT record_id, table_name, MAX(version) AS max_v
    FROM public.encrypted_rows
    WHERE family_id = p_family_id
    GROUP BY record_id, table_name
  ),
  deleted AS (
    DELETE FROM public.encrypted_rows er
    WHERE er.family_id = p_family_id
      AND er.version < v_min_cursor
      AND NOT EXISTS (
        SELECT 1 FROM latest l
        WHERE l.record_id = er.record_id AND l.table_name = er.table_name
      )
    RETURNING 1
  )
  SELECT COUNT(*)::bigint FROM deleted;
END;
$$;

-- Re-state the ACL from 0027: CREATE OR REPLACE resets the function's ACL to
-- owner-defaults, potentially re-exposing EXECUTE to authenticated/anon roles
-- that were explicitly revoked. Repeat the REVOKE/GRANT to be safe.
REVOKE EXECUTE ON FUNCTION public.compact_family_versions(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.compact_family_versions(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.compact_family_versions(uuid) FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.compact_family_versions(uuid) TO service_role;

COMMIT;
