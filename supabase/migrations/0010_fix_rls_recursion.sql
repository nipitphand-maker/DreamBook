-- Fix: infinite recursion in family_devices_select RLS policy.
-- The old policy queried family_devices to check family membership IN family_devices,
-- causing PostgreSQL to recurse infinitely when encrypted_rows policy triggered it.
-- Fix: SECURITY DEFINER helper that bypasses RLS to break the cycle.

CREATE OR REPLACE FUNCTION public.current_device_family_ids()
RETURNS SETOF uuid
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public
AS $$
  SELECT family_id FROM public.family_devices
  WHERE device_fp = uuid_send(auth.uid())
    AND revoked_at IS NULL;
$$;

-- Replace recursive policy with non-recursive version using the helper
DROP POLICY IF EXISTS family_devices_select ON public.family_devices;

CREATE POLICY family_devices_select ON public.family_devices
  FOR SELECT USING (
    family_id IN (SELECT public.current_device_family_ids())
  );

-- Fix encrypted_rows INSERT: was missing WITH CHECK, add it
DROP POLICY IF EXISTS encrypted_rows_insert ON public.encrypted_rows;

CREATE POLICY encrypted_rows_insert ON public.encrypted_rows
  FOR INSERT WITH CHECK (
    family_id IN (SELECT public.current_device_family_ids())
    AND written_by_device = uuid_send(auth.uid())
  );
