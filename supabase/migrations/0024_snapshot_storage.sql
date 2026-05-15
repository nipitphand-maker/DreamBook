-- supabase/migrations/0024_snapshot_storage.sql
-- Creates the private family-snapshots storage bucket.
-- All access is via Edge Functions (service_role). No direct client access.
BEGIN;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'family-snapshots',
  'family-snapshots',
  false,
  5242880,
  ARRAY['application/octet-stream']
)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "family_snapshots_deny_direct" ON storage.objects
  FOR ALL TO authenticated, anon
  USING (bucket_id = 'family-snapshots'
    AND false);

COMMIT;
