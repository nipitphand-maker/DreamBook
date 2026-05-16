-- Replace the single-column UNIQUE on device_fp with a compound
-- (device_fp, family_id) unique index so the same physical device can
-- join multiple families without silently overwriting its binding in the
-- first family when it joins a second.
--
-- The old implicit UNIQUE on device_fp (if any) is dropped first.
-- If family_devices has a PK or UNIQUE on device_fp alone, adjust the
-- DROP below to match the actual constraint name in your schema.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'family_devices_device_fp_key'
      AND conrelid = 'public.family_devices'::regclass
  ) THEN
    ALTER TABLE public.family_devices
      DROP CONSTRAINT family_devices_device_fp_key;
  END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS family_devices_fp_family_unique
  ON public.family_devices (device_fp, family_id);
