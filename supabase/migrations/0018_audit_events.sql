CREATE TABLE public.audit_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id uuid REFERENCES public.families(id) ON DELETE SET NULL,
  actor_device_fp bytea,
  event_type text NOT NULL CHECK (event_type IN (
    'family_created', 'invite_created', 'invite_claimed', 'invite_failed',
    'device_revoked', 'key_rotated', 'snapshot_uploaded', 'snapshot_restored',
    'recovery_attempted', 'recovery_succeeded', 'support_action', 'erasure_requested',
    'count_attestation_mismatch',
    'sync_background_started', 'sync_background_finished', 'realtime_reconnected'
  )),
  event_data jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_events_by_family ON public.audit_events(family_id, created_at DESC);
ALTER TABLE public.audit_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY audit_events_select ON public.audit_events
  FOR SELECT TO authenticated
  USING (family_id IN (SELECT public.current_user_family_ids()));
GRANT INSERT ON public.audit_events TO service_role;
