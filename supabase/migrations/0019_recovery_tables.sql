CREATE TABLE public.family_recovery_envelopes (
  family_id uuid PRIMARY KEY REFERENCES public.families(id) ON DELETE RESTRICT,
  wrapped_key bytea NOT NULL,
  salt bytea NOT NULL,
  key_version int NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.family_recovery_envelopes ENABLE ROW LEVEL SECURITY;
CREATE POLICY fre_select ON public.family_recovery_envelopes
  FOR SELECT TO authenticated
  USING (family_id IN (SELECT public.current_user_family_ids()));
GRANT SELECT, INSERT, UPDATE ON public.family_recovery_envelopes TO authenticated;

CREATE TABLE public.recovery_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id uuid NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  attempted_at timestamptz NOT NULL DEFAULT now(),
  success boolean NOT NULL,
  client_ip_hash bytea
);
CREATE INDEX recovery_attempts_recent ON public.recovery_attempts(family_id, attempted_at DESC);
ALTER TABLE public.recovery_attempts ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT ON public.recovery_attempts TO service_role;

CREATE TABLE public.recovery_lookup (
  lookup_hash bytea PRIMARY KEY,
  family_id uuid NOT NULL REFERENCES public.families(id) ON DELETE CASCADE
);
ALTER TABLE public.recovery_lookup ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, DELETE ON public.recovery_lookup TO service_role;
