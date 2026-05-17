-- Grant service_role direct SELECT on families so cron EFs
-- (cleanup_tombstones, compact_encrypted_rows) can enumerate families.
-- Grant service_role SELECT + DELETE on encrypted_rows so cleanup_tombstones
-- can hard-delete tombstoned rows.
GRANT SELECT ON public.families TO service_role;
GRANT SELECT, DELETE ON public.encrypted_rows TO service_role;
