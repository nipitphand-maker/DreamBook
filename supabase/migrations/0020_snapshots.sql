CREATE TABLE public.encrypted_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id uuid NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  version int NOT NULL,
  storage_path text NOT NULL,
  wrapped_key bytea NOT NULL,
  salt bytea NOT NULL,
  payload_hash bytea NOT NULL,
  size_bytes int NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_accessed_at timestamptz,
  UNIQUE (family_id, version)
);
CREATE INDEX encrypted_snapshots_by_family ON public.encrypted_snapshots(family_id, version DESC);
ALTER TABLE public.encrypted_snapshots ENABLE ROW LEVEL SECURITY;
CREATE POLICY snapshots_select ON public.encrypted_snapshots
  FOR SELECT TO authenticated
  USING (family_id IN (SELECT public.current_user_family_ids()));
GRANT SELECT ON public.encrypted_snapshots TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.encrypted_snapshots TO service_role;
