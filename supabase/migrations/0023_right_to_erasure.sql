BEGIN;
CREATE OR REPLACE FUNCTION public.right_to_be_forgotten(p_family_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_audit_id uuid;
BEGIN
  INSERT INTO public.audit_events (family_id, event_type, event_data)
  VALUES (p_family_id, 'erasure_requested', jsonb_build_object('source', 'user_request'))
  RETURNING id INTO v_audit_id;

  DELETE FROM public.encrypted_snapshots WHERE family_id = p_family_id;
  DELETE FROM public.encrypted_rows WHERE family_id = p_family_id;
  DELETE FROM public.key_distribution WHERE family_id = p_family_id;
  DELETE FROM public.invites WHERE family_id = p_family_id;
  DELETE FROM public.family_recovery_envelopes WHERE family_id = p_family_id;
  DELETE FROM public.recovery_attempts WHERE family_id = p_family_id;
  DELETE FROM public.device_sync_cursors WHERE family_id = p_family_id;
  DELETE FROM public.family_devices WHERE family_id = p_family_id;
  DELETE FROM public.families WHERE id = p_family_id;

  UPDATE public.audit_events
    SET event_data = event_data || '{"erased": true}'::jsonb
    WHERE id = v_audit_id;
END;
$$;
COMMIT;
