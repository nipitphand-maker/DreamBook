# DreamBook v1.0 — Sync, Recovery & Production Hardening Design

**Status:** Design ready for implementation planning
**Author:** Niyoko Studio
**Date:** 2026-05-15
**Spec version:** 1.0
**Prior specs:**
- `docs/superpowers/specs/2026-05-13-dreambook-design.md` (product spec)
- `docs/superpowers/specs/2026-05-14-plan-c-sync-crypto-design.md` (initial sync design)

---

## 1. Context & Problem Statement

DreamBook v1.0 (privacy-first baby daybook, Flutter + Supabase, sibling to DreamBaby) has reached a point where sync between family devices has failed in production 5 times across Plan C-2 and Plan D. The most recent failure (2026-05-15) is a `bytea` decode TypeError on the pull path that is invisible to unit tests because the fake Supabase adapter returns `Uint8List` directly while the real PostgREST returns base64 `String`.

A senior-team audit (DBA, Flutter engineer, SRE, Security reviewer, Lead Architect) found that the failure pattern is structural, not isolated:

- **40+ files and 9 migrations (0005–0016) are uncommitted** on `feat/plan-d-premium`. No checkpoint to roll back to.
- **`encrypted_rows_insert` RLS dropped its guards** (`written_by_device`, `key_version`) in migration 0011 — any family member can spoof writes.
- **`encrypted_rows_update` has no row-ownership predicate** — anyone can clobber anyone's row.
- **`create_invite` Edge Function doesn't forward caller auth** — anyone with a scraped pubkey can mint invites.
- **No real-adapter integration tests** — every failure layer was caught only in production.
- **No backup or restore path** for sole-admin phone loss; BIP-39 was deferred to v1.1.
- **No audit log, no staging environment, no migration linter** — every fix risks the next regression.

Meanwhile the project owner has committed to deliver a working multi-device family-sync app to a friend (mom + dad shared load). The promise needs to be kept.

This spec defines a **6-week production-hardening plan** with four mutually-reinforcing layers:

1. **Sync that doesn't lie** — fix the bytea bug, add retry/backoff, persist sync state, reconnect realtime, surface errors.
2. **RLS that defends** — restore dropped guards, lock row updates, authenticate invite minters, index predicates.
3. **Recovery that customers can self-serve** — Tier 1 (family device re-invite), Tier 2 (BIP-39, mandatory at setup), Tier 3 (encrypted cloud snapshot, opt-in premium).
4. **Operations that catch the next bug before users do** — staging Supabase, GitHub Actions CI, migration linter, audit log, customer support runbook.

---

## 2. Locked-in Decisions

Four decisions made during brainstorming on 2026-05-15:

| Axis | Decision | Rationale |
|---|---|---|
| **Scope** | **B — Production-ready in 4–6 weeks** | Friend's beta is the first milestone, not the finish line. Public Play Store launch is the target. |
| **Recovery tiers** | **T1 + T2 + T3 (T3 opt-in premium)** | Privacy-first stack: family device re-invite + BIP-39 phrase + optional encrypted cloud snapshot. T4 (email recovery) and T5 (vendor-held key) excluded to preserve E2E claim. |
| **Multi-family per user** | **Premium-gated multi-family** | Grandma persona (helping two daughters) is real and supported by existing namespaced secure storage (`dreambook_family_key_v1::${familyId}`). Free tier = 1 family slot. |
| **Operational maturity** | **Standard tier** | Staging Supabase + GitHub Actions CI + real-adapter integration tests + migration linter + audit log + right-to-erasure SQL function. Full-tier customer support dashboard deferred. |
| **Sequencing** | **Approach 1 — sequential, stabilize first** | Lowest risk. Friend's beta lands at Week 5 (Phase 5 exit) after BIP-39 and snapshot are working. |
| **Inactive family data retention** | **Option A — never auto-delete, tier to cold storage** | Privacy-first; auto-deletion is paternalistic and unreliable; cold-storage cost is ~$2/month at 10K abandoned families. |

---

## 3. Standing Senior Team

Six named senior agent roles ship this project. The team is constant across all phases; the **phase-exit gate is a blocking serial review pass by all four review roles**.

| Role | Responsibility | Owns |
|---|---|---|
| **Lead Architect** | Design coherence, cross-phase consistency, scope guard | Phase exit sign-off |
| **Postgres DBA** | Migrations, RLS policies, grants, indexes, query perf | `supabase/migrations/*.sql` |
| **Flutter Engineer** | Dart sync/crypto/UI code, local SQLCipher migrations | `lib/` |
| **Security Reviewer** | Crypto correctness, threat model, RLS bypass tests | Adversarial pass each Friday |
| **QA Auditor** | Real-adapter integration tests, regression scan, count attestation | `test/integration/` |
| **SRE / DevOps** | Staging, CI, migration linter, monitoring, audit log infra | `.github/workflows/`, observability |

### Phase-exit checklist (blocking, every Friday)

1. ☐ All planned tasks for the phase have green real-adapter integration tests
2. ☐ Migration linter passes (no new RLS regressions, no untyped bytea sites)
3. ☐ Security Reviewer adversarial pass: tries to spoof `written_by_device`, replay invites, brute-force phrases — all must fail
4. ☐ QA Auditor count attestation: # of rows server vs sum across devices in test family = match
5. ☐ Lead Architect sign-off: "Does the phase exit leave the system in a coherent state, or did we introduce hidden debt?"

---

## 4. 6-Week Phase Plan

| Week | Theme | Exit gate |
|---|---|---|
| **1** | **Triage** — commit current uncommitted files to `checkpoint/plan-d-pre-hardening` tag. Fix bytea decode bug (5 sites). Restore RLS guards (migration 0017). Write real-adapter integration tests proving pull works. | Sync provably green against real Supabase. |
| **2** | **Ops foundation** — staging Supabase project, GitHub Actions CI (lint + integration tests on every PR), migration linter, `audit_events` table + writers, `device_sync_cursors` table, `compact_encrypted_rows` Edge Function on cron. Auto-sync triggers shipped (WorkManager / BGTaskScheduler). | CI blocks bad migrations. Audit log records every key event. Compaction job runs daily without stranding offline devices. |
| **3** | **Recovery T1 + T2** — BIP-39 phrase generation at onboarding, write-down screen, restore-from-phrase screen, family-device re-invite UX. | Lost-phone-with-phrase test passes end-to-end. |
| **4** | **Recovery T3** — encrypted cloud snapshot with user passphrase (opt-in premium, per-family), snapshot upload/download, version pruning. | Snapshot round-trip test passes end-to-end. |
| **5** | **Multi-family + premium gate** — family picker, secure storage namespacing UI, RC entitlement check at family-creation, beta to friend. | Friend onboarded on his phone + his wife on hers. |
| **6** | **Polish + launch readiness** — customer support runbook + script, monitoring dashboards (Sentry + Supabase), GDPR right-to-erasure SQL function, store assets. | Public Play Store staged rollout (10% → 50% → 100%). |

**Out of scope (deferred to v1.1):**
- Co-admin promotion (made redundant by BIP-39)
- Shamir secret sharing
- Customer support read-only dashboard (Standard tier deferred this)
- P2P fallback sync

---

## 5. Database Hardening + Audit Log

### 5.1 Migration `0017_rls_reharden.sql`

Closes the 5 RLS regressions identified by the DBA audit.

**Restore `encrypted_rows_insert` guards:**

```sql
DROP POLICY IF EXISTS encrypted_rows_insert ON public.encrypted_rows;
CREATE POLICY encrypted_rows_insert ON public.encrypted_rows
  FOR INSERT TO authenticated
  WITH CHECK (
    family_id IN (SELECT current_user_family_ids())
    AND written_by_device = (
      SELECT encode(device_fp, 'hex')
      FROM public.family_devices
      WHERE auth_user_id = auth.uid()
      AND revoked_at IS NULL
      LIMIT 1
    )
    AND key_version = (
      SELECT current_key_version FROM public.families WHERE id = family_id
    )
  );
```

**Lock `encrypted_rows_update` row-ownership** — only the writing device can update its own version row:

```sql
DROP POLICY IF EXISTS encrypted_rows_update ON public.encrypted_rows;
CREATE POLICY encrypted_rows_update ON public.encrypted_rows
  FOR UPDATE TO authenticated
  USING (
    family_id IN (SELECT current_user_family_ids())
    AND written_by_device = (
      SELECT encode(device_fp, 'hex') FROM public.family_devices
      WHERE auth_user_id = auth.uid() AND revoked_at IS NULL LIMIT 1
    )
  )
  WITH CHECK (family_id IN (SELECT current_user_family_ids()));
```

**Explicit grants** on `families` and `family_devices`:

```sql
GRANT SELECT ON public.families TO authenticated;
GRANT SELECT ON public.family_devices TO authenticated;
```

**Indexes** killing the table-scan on every encrypted_rows fetch:

```sql
CREATE INDEX IF NOT EXISTS family_devices_auth_user_id_idx
  ON public.family_devices(auth_user_id) WHERE auth_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS family_devices_device_fp_active_idx
  ON public.family_devices(device_fp) WHERE auth_user_id IS NOT NULL AND revoked_at IS NULL;
```

### 5.2 `create_invite` Edge Function — authenticate caller

The current function uses a bare anon client and trusts the pubkey hash. **Change:** forward caller JWT, resolve `auth.uid()`, verify caller is an active admin via `family_devices.auth_user_id` lookup. Reject 401 otherwise.

### 5.3 New table `audit_events`

Append-only, 1-year retention. Schema:

```sql
CREATE TABLE public.audit_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id uuid REFERENCES public.families(id) ON DELETE SET NULL,
  actor_device_fp bytea,
  event_type text NOT NULL CHECK (event_type IN (
    'family_created', 'invite_created', 'invite_claimed', 'invite_failed',
    'device_revoked', 'key_rotated', 'snapshot_uploaded', 'snapshot_restored',
    'recovery_attempted', 'recovery_succeeded', 'support_action', 'erasure_requested',
    'count_attestation_mismatch'
  )),
  event_data jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_events_by_family ON public.audit_events(family_id, created_at DESC);
ALTER TABLE public.audit_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY audit_events_select ON public.audit_events
  FOR SELECT TO authenticated
  USING (family_id IN (SELECT current_user_family_ids()));
-- INSERT only via SECURITY DEFINER from Edge Functions.
```

### 5.4 New table `encrypted_snapshots` (Tier-3 backing store)

```sql
CREATE TABLE public.encrypted_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id uuid NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  version int NOT NULL,
  storage_path text NOT NULL,  -- Supabase Storage path
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
```

Retention: last 3 versions per family; auto-prune after 1 year unused.

### 5.5 New table `family_recovery_envelopes` (Tier-2 backing store)

```sql
CREATE TABLE public.family_recovery_envelopes (
  family_id uuid PRIMARY KEY REFERENCES public.families(id) ON DELETE CASCADE,
  wrapped_key bytea NOT NULL,
  salt bytea NOT NULL,
  key_version int NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.family_recovery_envelopes ENABLE ROW LEVEL SECURITY;
```

Re-wrapped on every key rotation by the rotating admin device.

### 5.6 New table `device_sync_cursors` (server-side, enables version compaction)

```sql
CREATE TABLE public.device_sync_cursors (
  family_id uuid NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  device_fp bytea NOT NULL REFERENCES public.family_devices(device_fp) ON DELETE CASCADE,
  last_pulled_at timestamptz NOT NULL DEFAULT now(),
  last_pulled_version_max bigint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (family_id, device_fp)
);
ALTER TABLE public.device_sync_cursors ENABLE ROW LEVEL SECURITY;
CREATE POLICY device_sync_cursors_select ON public.device_sync_cursors
  FOR SELECT TO authenticated
  USING (family_id IN (SELECT current_user_family_ids()));
CREATE POLICY device_sync_cursors_upsert ON public.device_sync_cursors
  FOR INSERT TO authenticated
  WITH CHECK (
    family_id IN (SELECT current_user_family_ids())
    AND device_fp = (
      SELECT device_fp FROM public.family_devices
      WHERE auth_user_id = auth.uid() AND revoked_at IS NULL LIMIT 1
    )
  );
CREATE POLICY device_sync_cursors_update ON public.device_sync_cursors
  FOR UPDATE TO authenticated
  USING (
    family_id IN (SELECT current_user_family_ids())
    AND device_fp = (
      SELECT device_fp FROM public.family_devices
      WHERE auth_user_id = auth.uid() AND revoked_at IS NULL LIMIT 1
    )
  );
```

Each device upserts its cursor after every successful pull. `compact_encrypted_rows` (§7.3 lever 2) uses `min(last_pulled_version_max)` across non-revoked devices in a family to decide which superseded versions are safe to hard-delete.

### 5.7 New table `recovery_attempts` (rate-limit log)

```sql
CREATE TABLE public.recovery_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id uuid NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  attempted_at timestamptz NOT NULL DEFAULT now(),
  success boolean NOT NULL,
  client_ip_hash bytea
);
CREATE INDEX recovery_attempts_recent ON public.recovery_attempts(family_id, attempted_at DESC);
```

Rate-limit logic in `claim_recovery` Edge Function: max 5 attempts/hour/family_id. 6th attempt → 1h cooldown.

### 5.8 Right-to-erasure function

```sql
CREATE OR REPLACE FUNCTION public.right_to_be_forgotten(p_family_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.audit_events (family_id, event_type, event_data)
  VALUES (p_family_id, 'erasure_requested', jsonb_build_object('source', 'user_request'));
  DELETE FROM public.encrypted_snapshots WHERE family_id = p_family_id;
  DELETE FROM public.encrypted_rows WHERE family_id = p_family_id;
  DELETE FROM public.key_distribution WHERE family_id = p_family_id;
  DELETE FROM public.invites WHERE family_id = p_family_id;
  DELETE FROM public.family_recovery_envelopes WHERE family_id = p_family_id;
  DELETE FROM public.recovery_attempts WHERE family_id = p_family_id;
  DELETE FROM public.device_sync_cursors WHERE family_id = p_family_id;
  DELETE FROM public.family_devices WHERE family_id = p_family_id;
  DELETE FROM public.families WHERE id = p_family_id;
  UPDATE public.audit_events SET event_data = '{"erased": true}'::jsonb
    WHERE family_id = p_family_id;
END;
$$;
```

### 5.9 Migration linter (CI-enforced)

`tool/lint_migrations.dart` runs in CI. Rules:

1. Every new table → RLS enabled + explicit grants declared.
2. Every `bytea` column → has a matching documented Dart decoder via `_decodeBytes`.
3. Every `CREATE POLICY` must have a matching `DROP POLICY IF EXISTS` for any same-name predecessor.
4. Schema diff vs prod required in PR description (blocks drift).
5. No `ALTER TABLE ... DROP COLUMN` without a deprecation note.

---

## 6. Sync Protocol Hardening

### 6.1 The bytea fix — single helper at all 5 sites

```dart
static Uint8List _decodeBytes(dynamic v) {
  if (v is Uint8List) return v;
  if (v is List)      return Uint8List.fromList(v.cast<int>());
  if (v is String) {
    if (v.startsWith(r'\x')) {
      return Uint8List.fromList(List.generate(
        v.length ~/ 2 - 1,
        (i) => int.parse(v.substring(2 + i*2, 4 + i*2), radix: 16)));
    }
    return base64Decode(v);
  }
  throw ArgumentError('bytea: unexpected ${v.runtimeType}');
}
```

Applied in `lib/core/sync/supabase_sync_server.dart`:
- `pullRows` line 98–99 (ciphertext, aad_hash)
- `realtimeStream` line 133–135 (ciphertext, aad_hash)
- `pullKeyDistribution` line 164 (wrapped_key)

**Unit test forces all 4 input shapes** — Uint8List, List<int>, hex-string, base64-string.

### 6.2 Retry/backoff layer

New `RetryPolicy` in `lib/core/sync/retry_policy.dart`:
- Max 5 attempts
- Exponential backoff 1s → 2s → 4s → 8s → 16s + ±20% jitter
- Wraps push, pull, snapshot upload, snapshot download

Classifies errors:
- **Transient** (`SocketException`, `TimeoutException`, HTTP 5xx, PostgrestException `PGRST204`) → retry
- **Terminal** (HTTP 4xx except 408/429, `TypeError`, MAC verification fail) → fail fast, audit log + Sentry breadcrumb

### 6.3 Realtime reconnect

`RealtimeSubscriber.onError` now triggers exponential reconnect (1s → 30s cap). `RealtimeStatus` enum surfaced to UI (`connected | degraded | offline`). The "degraded" UI indicator from commit `845e722` finally has a state machine behind it.

### 6.4 Persistent `_lastPullAt`

Moved from in-memory to new SQLite table `sync_cursors(family_id, last_pull_at)`. Cold start = incremental pull, not full re-pull.

### 6.5 Non-silent errors

Replace `sync_lifecycle_controller.dart:79-82` swallow with:
1. Write to `audit_events` (server-side, via Edge Function)
2. Sentry capture with sanitized payload (no ciphertext, no keys, no PII)
3. Keep `SyncStatus.failed` for UI

### 6.6 Tombstone correctness

`deleted_at` rows still flow through pull but `_applyIncoming` issues a local DELETE instead of upsert. Tombstone retention stays at **90 days** server-side (cron `cleanup_tombstones`).

---

## 7. Auto-Sync Triggers + Storage Efficiency

### 7.1 Auto-sync — five triggers, layered for "never fail to catch up"

| Trigger | When | What it catches |
|---|---|---|
| Realtime websocket | Both apps foregrounded | Instant push during shared session |
| App-lifecycle resume | App enters foreground | Anything that happened while backgrounded |
| Network reconnect | `connectivity_plus` transitions offline→online | Everything missed offline |
| Post-write debounce 500ms | Local write done | Smoothes burst writes |
| **Periodic background (NEW v1.0)** | WorkManager Android (15min on Wi-Fi+charging, 60min otherwise) / BGAppRefreshTask iOS | Data when app never opened |

All five paths converge on `syncNow()`. Background trigger sets `SyncTrigger.background` in audit log for debugging.

**Note:** Background sync was previously deferred to v1.1 — pulling it forward because "dad logs feed while mom's phone in pocket" is the core family-share scenario.

### 7.2 Sync completeness guarantees

1. **Per-table count attestation** — after every pull, client compares `local_count(table, family_id, NOT deleted)` vs server count. Mismatch → log `count_attestation_mismatch` event + trigger full re-pull from `time=0`.
2. **Sync health UI** — `Last sync: 2m ago • 247 records ✓ • all devices ≤5m behind`. If a device hasn't synced in >24h, in-app banner prompt (not push).
3. **Resync-from-scratch fallback** — if `sync_cursors` row missing/corrupted or count check fails 3× consecutively, drop cursor and full-pull. Idempotent thanks to deterministic UUID v5 keys + `aad_hash` MAC verification.

### 7.3 Storage efficiency — 3 levers (target ≤1MB/family/year)

1. **Pre-encryption zstd compression** in `CryptoEnvelope.seal()` — baby logs are highly repetitive JSON; expect 60–80% reduction. Adds ~3ms/row.
2. **Version compaction job** — daily Edge Function `compact_encrypted_rows` (built Week 2): for each `(family_id, table_name, record_id)`, query `device_sync_cursors` for `min(last_pulled_version_max)` across non-revoked devices, hard-delete all versions `< min` (Sync Safety Invariant SSI-2 — latest non-tombstoned version preserved regardless). Skips compaction for families where any device hasn't synced in >7 days (defensive: don't strand offline devices).
3. **Snapshot storage in Supabase Storage bucket** — `family-snapshots/{family_id}/v{n}.bin`, not Postgres bytea. ~80% cheaper per GB.

Combined: active family generating 10 events/day → **~0.7MB/year**. 10K families = ~7GB Postgres (~$0.90/month).

### 7.4 Inactive family retention (Option A — never auto-delete)

| Age | Storage tier | Action |
|---|---|---|
| 0–12 months inactive | Postgres `encrypted_rows` (hot) | Normal sync |
| 12+ months inactive | Supabase Storage standard (warm) | Migrate + re-compress |
| 24+ months inactive | Supabase Storage cold | Dictionary-compress |
| **Never** | — | **No auto-delete.** Only user-initiated `right_to_be_forgotten`. |

Cost at scale: 10K abandoned families ≈ 70GB cold = ~$1.75/month.

### 7.5 Sync Safety Invariants

- **SSI-1** No active row is ever hard-deleted by the server. Only `deleted_at IS NOT NULL` rows are eligible for purge.
- **SSI-2** Version compaction only operates on superseded versions. The latest non-tombstoned version is never deleted, even if all devices have pulled past it.
- **SSI-3** Tombstone purge only fires after 90 days. Configurable per family via `families.tombstone_retention_days`.
- **SSI-4** Right-to-erasure is the only path that bypasses SSI-1. Logged in `audit_events`. User-initiated only.

Real-adapter integration tests verify each invariant with adversarial scenarios (offline device returns after retention window, etc).

---

## 8. Recovery System (Tiers 1 + 2 + 3)

### 8.1 Tier 1 — Family Device Recovery (free, automatic)

**Scenario:** Mom loses phone; dad's app still works.

**Flow:**
1. Dad opens DreamBook → Settings → Manage Devices → sees "Mom's iPhone — last sync 3 days ago — ⚠️ inactive"
2. Tap "Help mom set up new phone" → generates new invite code (8-char Crockford base32, 1h TTL, single-use; matches Plan C D1 invite-code format)
3. Dad shares code with mom out-of-band
4. Mom installs DreamBook → "I'm a returning user" → enters code → `claim_invite_atomic` returns wrapped K_family → device fingerprint replaces previous → full pull catches her up
5. Old device auto-revoked with `revoke_reason = 'replaced_by_recovery'`
6. Audit log: `device_recovered_via_invite`, push to all other devices: "Mom's new device joined the family"

**Test:** simulate mom's device wipe → dad issues invite → mom's new device receives 100% of history within 30s on broadband.

### 8.2 Tier 2 — BIP-39 Recovery Phrase (mandatory at setup, free)

**Scenario:** Mom is sole admin OR both family phones lost simultaneously.

**Onboarding (mandatory step, can't skip):**
1. Generate 12-word BIP-39 phrase from CSPRNG (128-bit entropy + 4-bit checksum word)
2. Show on screen, ask user to write down. `FLAG_SECURE` blocks screenshots.
3. Verification: "Type word 3 and word 9" — fail twice → regenerate phrase
4. Derive recovery key via Argon2id(phrase, salt, m=64MiB, t=3, p=1) → 256-bit key
5. AES-GCM-wrap K_family with recovery key (AAD = `family_id|key_version`)
6. Upload to `family_recovery_envelopes`
7. **Re-wrap on every key rotation** — handled atomically in rotate-key flow

**Restore flow:**
1. Onboarding → "Restore from recovery phrase" → enter 12 words
2. Client validates BIP-39 checksum locally (catches typos before hitting server)
3. POST `claim_recovery` Edge Function with `family_id_hint` (lookup via `recovery_lookup` hash, not exposing family graph)
4. Server returns envelope; client unwraps with Argon2id-derived key
5. Success: new device added to family_devices, audit log entry, push to all family devices
6. Rate limit: 5 attempts/hour/family_id (tracked in `recovery_attempts`). 6th → 1h cooldown.

**Edge case — partial recovery:** if phrase was generated before a key rotation, server keeps rotation chain re-wrapped under recovery key. Restoring user gets current K_family.

**Argon2id fallback:** On Android API 23 baseline, if 64MiB OOMs, fall back to m=32MiB (pre-approved in Plan C §9). Benchmark on emulator API 23 before Week 3 implementation.

### 8.3 Tier 3 — Encrypted Cloud Snapshot (opt-in premium, user passphrase)

**Scenario:** "I have neither the phrase nor another family device" — last-resort lifeline.

**Setup (Settings → Cloud Backup, premium-gated):**
1. User picks a passphrase (≥12 chars; app suggests Diceware-style for entropy)
2. Daily background job (Wi-Fi+charging) or on-demand:
   - Bundle full family rows + key_distribution + local audit log into JSON
   - zstd-compress, AES-GCM encrypt with Argon2id(passphrase)-derived key
   - Upload to Supabase Storage `family-snapshots/{family_id}/v{n}.bin`
   - Insert metadata in `encrypted_snapshots`
3. Retention: last 3 versions per family. Auto-prune after 1 year unused.
4. **Recovery card** generated at setup — printable card with family_id + first 4 chars of passphrase hint. User stores offline (wallet, safe).

**Restore:**
1. Onboarding → "Restore from cloud backup" → enter passphrase + family_id (from recovery card or in-app QR from another device)
2. Server rate-limits; if OK, returns signed URL to latest snapshot blob
3. Client downloads, decrypts with passphrase-derived key, restores entire family locally + rejoins family_devices

### 8.4 Threat model summary

| Attack | Defense | Surviving guarantee |
|---|---|---|
| Server fully compromised | All payloads encrypted, all wrap keys derived client-side | Attacker gets ciphertext only |
| Brute-force BIP-39 phrase | 128-bit entropy + Argon2id m=64MiB | ~10²⁵ years on attacker GPU |
| Brute-force snapshot passphrase | Argon2id + rate limit 5/h/family | Practically infeasible for ≥12-char passphrase |
| User loses phone + phrase + passphrase | None — by design | Data unrecoverable. Disclosed at setup. |
| Stolen phone tries to keep syncing | T1 auto-revokes old device | Locked out; revoke propagates on next online |
| Spoofed `written_by_device` | RLS predicate forces `device_fp = auth.uid()'s device` | INSERT rejected |
| Replay of invite | `code_hash` single-use, `consumed_at` set atomically | Reuse rejected |
| Snapshot from family A restored as family B | AAD binds family_id; unwrap fails | Rejected on decrypt |

### 8.5 Customer support runbook

When a customer messages "I lost my phone":
1. **Ask:** "Do you have your 12-word recovery phrase?" → Tier 2 walkthrough
2. **If no:** "Does another family member still have the app working?" → Tier 1 walkthrough
3. **If no:** "Did you set up Cloud Backup with a passphrase?" → Tier 3 walkthrough
4. **If no:** "Your data was encrypted with a key only you held. We have no way to decrypt it. This is the privacy tradeoff that protects all our users from data leaks." Plus goodwill: free month of premium.

---

## 9. Multi-family + Operational Foundation

### 9.1 Multi-family architecture

- **Storage:** single SQLCipher DB with `family_id` column on every table (Plan B m003 already added it).
- **Secure storage namespacing:** `dreambook_family_key_v1::${familyId}` for K_family. **Already implemented** at `lib/core/crypto/family_key_service.dart:97`. UI is the only new work.
- **Premium gate (RevenueCat):** free tier capped at 1 family; second family creation returns HTTP 402, prompts paywall. Caregivers joining via invite are **free regardless of host's tier** (preserves caregiver-share differentiator).
- **UI:** family picker in home screen header (hidden at count=1); "Add Another Family" CTA in onboarding + Settings → Families; per-family BIP-39 phrase + cloud snapshot; "Leave family" button per family.

### 9.2 Standing senior team — see Section 3

### 9.3 CI / staging / observability

- **Staging Supabase project** — separate ap-southeast-1, mirrors prod schema. Migrations applied via CI on merge to `staging` branch.
- **GitHub Actions CI** — runs on every PR:
  - `flutter analyze`
  - `flutter test` (unit, Ring 1)
  - `supabase start` + `flutter test integration_test/` (Ring 2 real-adapter)
  - `dart run tool/lint_migrations.dart`
  - Schema diff staging vs prod (block on unexpected drift)
- **Migration linter** — see §5.8
- **Audit log infrastructure** — `audit_events` table + Edge Function writers + 1-year retention cron
- **Sentry** — client crashes + sync errors. Strip ciphertext, keys, PII from breadcrumbs.
- **Supabase dashboard alerts** — 5xx rate >1%, Edge Function p95 latency >2s, storage growth >100MB/day.
- **Synthetic monitor** — automated test family syncs every 15min from CI-controlled emulator; pages SRE on 3 consecutive failures.

### 9.4 Customer support workflow (Standard tier — read-only dashboard deferred to v1.1)

- Direct SQL queries against staging mirror + `audit_events` filtering
- Pre-written SQL toolkit: "show me what device fingerprint X did in the last 7 days"
- Runbook PDF + Notion with §8.5 decision tree
- Support escape templates (goodwill premium offer wording, "we cannot decrypt" apology wording, recovery-phrase walkthrough screenshots)

---

## 10. Testing & Rollout

### 10.1 Three rings of tests

**Ring 1 — Unit tests** (existing 192, expanded to ~280)
- `_decodeBytes` all 4 input shapes
- `RetryPolicy` timing + classification
- BIP-39 round-trip (generate → derive → wrap → unwrap matches K_family)
- Argon2id parameter validation
- Sync Safety Invariants SSI-1 through SSI-4
- Runs on every commit

**Ring 2 — Real-adapter integration tests** ⭐ NEW
- Spins up `supabase start` in CI (Postgres + PostgREST + Realtime + Storage)
- Applies every migration in order
- Scenarios through actual `SupabaseSyncServer`:
  - 2-device family: write A → realtime push → appears on B within 5s
  - Offline device: A writes 50 rows offline → reconnect → push + B receives all 50
  - Tombstone: A deletes → B's local copy removed after pull
  - Conflict: A and B write same row offline → LWW resolves deterministically
  - Recovery T1: B revoked → re-invited → resyncs full history
  - Recovery T2: install new device → enter BIP-39 → recovers entire family
  - Recovery T3: install new device → enter passphrase → snapshot restored
  - Count attestation match after every scenario
- Runs on every PR. **Failure blocks merge.**

**Ring 3 — Adversarial / security tests** (Security Reviewer)
- Spoofed `written_by_device` rejected by RLS
- Stale `key_version` insert rejected by RLS
- Invite reuse rejected
- Brute-force BIP-39 hits rate limit after 5
- Replay attack on `claim_recovery` blocked
- MAC tamper on `encrypted_rows.ciphertext` rejected on decrypt
- Snapshot from family A cannot be restored as family B

### 10.2 6 phase gates + rollback strategy

| Week | Phase exit gate | Rollback strategy |
|---|---|---|
| **1 — Triage** | Bytea fix verified via Ring 2; migration 0017 on staging; 5 prior bugs covered by tests | Revert to tag `checkpoint/plan-d-pre-hardening` |
| **2 — Ops foundation** | CI green on staging; migration linter rejects regression PR test; audit log writes from all Edge Functions | Disable individual CI checks; staging is throwaway |
| **3 — T1+T2 recovery** | BIP-39 round-trip end-to-end on 2 devices; rate-limit test passes | Feature flag `recovery_v1_enabled` server-side |
| **4 — T3 snapshot** | Daily snapshot upload + restore round-trip; bucket RLS blocks cross-family read | Feature flag `snapshot_enabled`; bucket wipeable (redundant with T2) |
| **5 — Multi-family + beta** | Friend onboarded; wife joins via invite; both can write/read within 5s; lost-phone drill passes | RC entitlement gate is server-enforced |
| **6 — Public launch** | Privacy policy + first-launch disclosure; monitoring live; runbook approved; synthetic monitor green 7 days | Play Store staged rollout 10% → 50% → 100% over 7 days |

### 10.3 Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| Argon2id 64MiB OOMs on Android API 23 baseline | Medium | Fallback to m=32MiB pre-approved; benchmark Week 3 |
| PostgREST returns bytea in an unanticipated format | Low | `_decodeBytes` covers 4 shapes; Ring 2 catches on PR; throws with type info |
| Sole admin loses phone + phrase + passphrase | Low (multi-tier reduces) | Disclosed at onboarding; goodwill premium month |
| Migration drift staging vs prod resurfaces | Low (linter blocks) | Linter requires schema-diff output in PR description |
| Friend's beta exposes unforeseen sync race | Medium | Beta-1 gate has count attestation; Sentry captures all errors |

### 10.4 Post-launch — first 30 days

- Daily review of `audit_events` for anomalies (unusual failure rates, repeated brute force)
- Weekly Lead Architect retro: what broke, tech debt, what's working
- Synthetic monitor metrics: median sync latency, push success rate, recovery flow completion rate
- Goal: zero "sync failed" support tickets week 1; ≤1/week weeks 2–4

---

## 11. Privacy Policy & Disclosure Trail

User-facing documents updated as part of Phase 6:

| Document | What's added |
|---|---|
| **Privacy Policy** | "Active data is retained indefinitely in encrypted form. Records you delete are purged from our servers within 90 days. You can request full erasure at any time via Settings → Right to Erasure." |
| **In-app First-Launch Disclosure** | One-screen plain-language summary: "Your data lives on your device. We store an encrypted backup so you can recover it. Only you have the key." |
| **Help Center: "How long do you keep my data?"** | Detailed version with cold-storage tiering explanation |
| **Settings → About Your Data** | Live info: last sync, records on server, encrypted-MB used, recovery-phrase backed up ✓/✗, snapshot ✓/✗, "Delete All My Data" button |
| **Setup screen for BIP-39** | "If you lose this phrase AND your phone AND your family backup passphrase, we cannot recover your data — this is the privacy tradeoff." |

---

## 12. New Schema Inventory

Tables introduced by this spec:

1. `audit_events` — append-only event log, 1-year retention (server)
2. `encrypted_snapshots` — Tier-3 metadata; payloads in Storage bucket (server)
3. `family_recovery_envelopes` — Tier-2 BIP-39-wrapped K_family (server)
4. `recovery_attempts` — rate-limit log (server)
5. `recovery_lookup` — hash-based family_id lookup, no graph exposure (server)
6. `device_sync_cursors` — per-device per-family pull progress, enables version compaction (server)
7. `sync_cursors` — local SQLite table for persistent `last_pull_at` (client)

Modified tables:

- `families` adds `tombstone_retention_days int DEFAULT 90`, `last_active_at timestamptz`
- `encrypted_rows_insert` RLS — guards restored
- `encrypted_rows_update` RLS — row-ownership added
- `families`, `family_devices` — explicit grants added

New Storage bucket:

- `family-snapshots/` — Storage policies restrict to family members

---

## 13. Files Touched (estimate)

| Layer | New | Modified |
|---|---|---|
| Supabase migrations | `0017_rls_reharden.sql`, `0018_audit_events.sql`, `0019_recovery_tables.sql`, `0020_snapshots.sql`, `0021_device_sync_cursors.sql` | — |
| Edge Functions | `claim_recovery/`, `upload_snapshot/`, `restore_snapshot/`, `compact_encrypted_rows/` | `create_invite/`, `claim_invite/` |
| Dart core | `lib/core/sync/retry_policy.dart`, `lib/core/sync/sync_cursors.dart`, `lib/core/crypto/bip39_service.dart`, `lib/core/crypto/snapshot_service.dart`, `lib/core/sync/count_attestation.dart` | `lib/core/sync/supabase_sync_server.dart`, `lib/core/sync/sync_worker.dart`, `lib/core/sync/sync_lifecycle_controller.dart`, `lib/core/crypto/crypto_envelope.dart`, `lib/core/crypto/family_key_service.dart` |
| Dart features | `lib/features/recovery/` (BIP-39 setup + restore UI), `lib/features/snapshot/` (cloud backup UI), `lib/features/families/` (multi-family picker) | `lib/features/share/`, `lib/features/onboarding/`, `lib/features/settings/` |
| Background sync | `lib/core/background/workmanager_sync.dart`, `lib/core/background/ios_bg_refresh.dart` | `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist` |
| CI / tooling | `.github/workflows/ci.yml`, `tool/lint_migrations.dart`, `tool/schema_diff.dart` | — |
| Tests | `test/integration/sync_e2e_test.dart`, `test/integration/recovery_t1_test.dart`, `test/integration/recovery_t2_test.dart`, `test/integration/recovery_t3_test.dart`, `test/security/rls_adversarial_test.dart` | — |
| Docs | `docs/privacy-policy.md`, `docs/customer-support-runbook.md`, `docs/data-retention.md` | `README.md`, `CLAUDE.md` |

Estimated: ~25 new files, ~20 modified files.

---

## 14. Out of Scope (deferred to v1.1+)

- Co-admin promotion (redundant with BIP-39)
- Shamir secret sharing
- Customer support read-only dashboard (Standard tier deferred)
- P2P fallback sync
- WebAuthn-based recovery
- iOS-side App Group sync with DreamBaby (currently a separate bridge)

---

## 15. Open Questions

None at design time. All four axes locked during 2026-05-15 brainstorm.

---

**End of design.** Next step: invoke `superpowers:writing-plans` against this spec to produce a task-graph implementation plan.
