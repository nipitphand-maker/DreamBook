-- Allow the same physical device to join multiple families.
--
-- Previously family_devices.device_fp was the PRIMARY KEY, making device_fp
-- globally unique and preventing a device from appearing in more than one family.
-- Migration 0032 added a compound unique INDEX (device_fp, family_id) but did not
-- drop the original PK, so the single-column uniqueness constraint remained.
--
-- This migration:
--   1. Promotes the UNIQUE INDEX from 0032 to a UNIQUE CONSTRAINT — Postgres
--      requires a CONSTRAINT (not just an index) as a FK target.
--   2. Drops the FK in key_distribution that references family_devices(device_fp).
--   3. Drops the FK in device_sync_cursors that references family_devices(device_fp).
--   4. Drops the PRIMARY KEY constraint on device_fp.
--   5. Adds a surrogate bigserial primary key.
--   6. Recreates both FKs as compound references to (device_fp, family_id),
--      now backed by the promoted UNIQUE CONSTRAINT.

BEGIN;

-- 1. Promote the unique index to a constraint so it can be used as a FK target.
--    `ADD CONSTRAINT ... UNIQUE USING INDEX` converts an existing unique index into
--    a constraint in-place with no rewrite.
ALTER TABLE public.family_devices
  ADD CONSTRAINT family_devices_fp_family_unique
  UNIQUE USING INDEX family_devices_fp_family_unique;

-- 2. Drop the single-column FK in key_distribution (references device_fp alone).
ALTER TABLE public.key_distribution
  DROP CONSTRAINT IF EXISTS key_distribution_recipient_device_fp_fkey;

-- 3. Drop the single-column FK in device_sync_cursors (references device_fp alone).
ALTER TABLE public.device_sync_cursors
  DROP CONSTRAINT IF EXISTS device_sync_cursors_device_fp_fkey;

-- 4. Drop the PK that enforced global uniqueness on device_fp.
ALTER TABLE public.family_devices
  DROP CONSTRAINT IF EXISTS family_devices_pkey;

-- 5. Surrogate primary key (no business meaning — just a stable row identity).
ALTER TABLE public.family_devices
  ADD COLUMN IF NOT EXISTS id bigserial PRIMARY KEY;

-- 6a. Re-add the key_distribution FK as a compound reference.
ALTER TABLE public.key_distribution
  ADD CONSTRAINT key_distribution_device_family_fkey
  FOREIGN KEY (recipient_device_fp, family_id)
  REFERENCES public.family_devices(device_fp, family_id)
  ON DELETE CASCADE;

-- 6b. Re-add the device_sync_cursors FK as a compound reference.
--     device_sync_cursors already has both (device_fp, family_id) columns.
ALTER TABLE public.device_sync_cursors
  ADD CONSTRAINT device_sync_cursors_device_family_fkey
  FOREIGN KEY (device_fp, family_id)
  REFERENCES public.family_devices(device_fp, family_id)
  ON DELETE CASCADE;

COMMIT;
