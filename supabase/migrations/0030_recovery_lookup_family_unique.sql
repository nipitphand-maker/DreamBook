-- Make recovery_lookup.family_id unique so upload_recovery can upsert atomically.
-- Previously the EF did delete-then-insert (non-atomic: crash between them left
-- the family with no lookup entry, making the recovery code permanently unusable).
-- With this constraint, upsert on family_id is safe and atomic.
ALTER TABLE recovery_lookup
  ADD CONSTRAINT recovery_lookup_family_id_unique UNIQUE (family_id);
