CREATE TABLE public.device_sync_cursors (
  family_id uuid NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  device_fp bytea NOT NULL REFERENCES public.family_devices(device_fp) ON DELETE CASCADE,
  last_pulled_at timestamptz NOT NULL DEFAULT now(),
  last_pulled_version_max bigint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (family_id, device_fp)
);
ALTER TABLE public.device_sync_cursors ENABLE ROW LEVEL SECURITY;
CREATE POLICY dsc_select ON public.device_sync_cursors
  FOR SELECT TO authenticated
  USING (family_id IN (SELECT public.current_user_family_ids()));
CREATE POLICY dsc_upsert ON public.device_sync_cursors
  FOR INSERT TO authenticated
  WITH CHECK (
    family_id IN (SELECT public.current_user_family_ids())
    AND device_fp = (
      SELECT device_fp FROM public.family_devices
      WHERE auth_user_id = auth.uid() AND revoked_at IS NULL LIMIT 1
    )
  );
CREATE POLICY dsc_update ON public.device_sync_cursors
  FOR UPDATE TO authenticated
  USING (
    family_id IN (SELECT public.current_user_family_ids())
    AND device_fp = (
      SELECT device_fp FROM public.family_devices
      WHERE auth_user_id = auth.uid() AND revoked_at IS NULL LIMIT 1
    )
  );
GRANT SELECT, INSERT, UPDATE ON public.device_sync_cursors TO authenticated;
