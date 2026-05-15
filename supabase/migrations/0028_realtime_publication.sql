-- supabase/migrations/0028_realtime_publication.sql
--
-- Team 10 (paranoid audit, 2026-05-16) found that cross-device live sync was
-- silently dead because no migration ever added `encrypted_rows` (or the other
-- per-family tables) to the `supabase_realtime` publication. The Dart client
-- subscribes via `_client.channel('encrypted_rows:$familyId')`, the websocket
-- handshake succeeds, the subscription transitions to "joined" — but no row
-- events are ever published because Postgres logical replication is never told
-- to track INSERTs/UPDATEs on these tables. End result: every cross-device
-- push needs a manual pull-to-refresh to land on the peer; no UX of "the other
-- parent's feed entry just appeared."
--
-- Adds the read-write per-family tables to the publication. Service-role-only
-- tables (audit_events, recovery_*, encrypted_snapshots) stay off — they have
-- no live-UI consumer.

BEGIN;

ALTER PUBLICATION supabase_realtime ADD TABLE
  public.encrypted_rows,
  public.key_distribution,
  public.family_devices;

COMMIT;
