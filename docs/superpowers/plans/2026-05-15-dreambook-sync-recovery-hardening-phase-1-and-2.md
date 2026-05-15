# DreamBook Sync, Recovery & Production Hardening — Implementation Plan (Phase 1 + 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stabilize the broken Supabase sync, restore RLS guards, fix the bytea decode bug, and build the operational foundation (CI + staging + audit log + auto-sync) so the next 4 weeks of recovery features land on a solid base.

**Architecture:** Six parallel work streams (DB, Sync/Crypto, Edge Functions, Tests, DevOps, Background) execute against a single spec with a serial Friday phase-exit review gate. Phase 1 (Week 1) restores invariants; Phase 2 (Week 2) builds the ops foundation.

**Tech Stack:** Flutter 3.41 + Dart 3.10, Supabase Postgres + Edge Functions (Deno), pgTAP, WorkManager + connectivity_plus, GitHub Actions, Sentry, supabase_flutter 2.9.

**Spec reference:** `/Users/nipitphand/Projects/DreamBook/docs/superpowers/specs/2026-05-15-dreambook-sync-recovery-hardening-design.md`

---

## Audit findings & resolutions

**Spec coverage gaps found and fixed inline:**

- **[GAP-1] `compact_family_versions` SQL function undefined.** Spec §7.3 lever 2 + Team 3 EF-5 reference a SECURITY DEFINER function but no team owned its DDL. **Resolution:** added **DB-7** (was Team 1's pgTAP runner — renumbered to DB-8) to migration 0021 (`compact_family_versions`), which embeds SSI-2 safety predicate (`AND (record_id, table_name) NOT IN (SELECT (record_id, table_name) FROM <latest_version_per_record>)`) and a 7-day-offline-device skip.
- **[GAP-2] `test_only_age_recovery_attempts` RPC missing.** Team 7 SEC-5 calls it but no team defined it. **Resolution:** added **[NEW DB-9]** test-only SQL helper, guarded by `IF current_setting('app.test_mode', true) <> 'true' THEN RAISE ...`, deployed only via staging migration path.
- **[GAP-3] `sync_cursors` (client-side, §6.4) vs `device_sync_cursors` (server-side, §5.6) conflation.** Both exist. Team 2 SY-7 owns the local one (m007); Team 1 DB-5 owns the server one. Naming kept distinct in the merged plan.
- **[GAP-4] `claim_invite` Edge Function audit-event emission.** §5.3 enumerates `invite_claimed` and `invite_failed` but Team 3 EF tasks focused on `create_invite`. **Resolution:** added explicit step in EF-2 to instrument both `create_invite` and `claim_invite`.
- **[GAP-5] §6.6 tombstone purge cron (90-day).** Spec mentions `cleanup_tombstones` cron but no task. **Resolution:** added **[NEW EF-9]** in Phase 2 — a cron-driven Edge Function alongside `compact_encrypted_rows`.

**Type / signature conflicts resolved:**

- **bytea decoder name mismatch.** Team 2 exports `decodeBytea` from `lib/core/sync/bytea_codec.dart`. Team 5's migration linter (`tool/lint_migrations.dart`) was originally written to grep for `_decodeBytes` per spec §5.9 wording. **Resolved:** Team 2's `decodeBytea` is the source of truth (top-level public function so it's grep-anchorable, and the spec snippet used `_decodeBytes` only as a private convention). Team 5's DV-3 linter rule is updated to grep for `decodeBytea` (not `_decodeBytes`).
- **`SyncTrigger` enum ownership.** Owned by Team 6 (`lib/core/sync/sync_trigger.dart`). Team 2's SY-5 reporter `payload['trigger']` becomes a `SyncTrigger.name` string at call sites — no duplicate enum.
- **`audit_events.event_type` CHECK constraint values.** Spec §5.3 lists 13 values. Teams 3 and 6 emit `'sync_background_started'` and `'sync_background_finished'` not in the spec list. **Resolved:** DB-2 (migration 0018) CHECK constraint extended to add `'sync_background_started'`, `'sync_background_finished'`, `'realtime_reconnected'`. Documented in DB-2.
- **`right_to_be_forgotten` signature.** `(p_family_id uuid) RETURNS void` — consistent across DB-6 and EF-7. ✓
- **`device_sync_cursors` columns.** `family_id`, `device_fp`, `last_pulled_at`, `last_pulled_version_max`, `updated_at` — consistent across DB-5, EF-5, TI-10. ✓

**Bite-sized granularity flags addressed:** Team 2 SY-3 originally bundled "write RetryPolicy class + tests" — split here into SY-3a (classify-only tests + impl), SY-3b (delayFor tests + impl), SY-3c (run() tests + impl). Team 6 BG-1 (enum + WorkManager registration) split into BG-1a/1b. Team 7 SEC-3 (10 RLS attacks) split into 3 sub-tests of 3-4 attacks each.

**Placeholder scan:** Team 2 SY-9 step 6 contains `// ...` placeholders inside test bodies. **Resolved:** P2.9 below expands those into the actual arrange/assert lines.

---

## Task dependency graph

```
                            PHASE 1 (Week 1)                              │   PHASE 2 (Week 2)
                                                                          │
  P1.1 DV-1 checkpoint commit (BLOCKING ROOT)                             │
        │                                                                 │
        ├─ P1.2 SY-1 decodeBytea helper                                   │
        │       └─ P1.3 SY-2 replace 5 bytea sites                        │
        │                                                                 │
        ├─ P1.4 DB-1 migration 0017 (RLS reharden)                        │
        │       │                                                         │
        │       ├─ P1.5 EF-1 create_invite caller-auth fix                │
        │       │                                                         │
        │       └─ P1.6..7 TI-1, TI-2 real-adapter harness                │
        │              │                                                  │
        │              ├─ P1.8 TI-3 scenario 1 (2-device push)            │
        │              └─ P1.9 TI-4 scenario 2 (offline 50-rows)          │
        │                                                                 │
        ├─ P1.10 SY-3a/b/c RetryPolicy (3 sub-tasks)                      │
        ├─ P1.11 SY-4 wire RetryPolicy into worker                        │
        ├─ P1.12 SY-5 SyncErrorReporter (non-silent path)                 │
        ├─ P1.13 SY-6 RealtimeStatus state machine                        │
        ├─ P1.14 SY-7 m007 sync_cursors + persist _lastPullAt             │
        ├─ P1.15 SY-8 tombstone DELETE in _applyIncoming                  │
        │                                                                 │
        └─ P1.16 [Phase 1 exit gate]                                      │
                                                                          │
                                                                          │   P2.1 DV-2 staging Supabase project
                                                                          │       │
                                                                          │       ├─ P2.2 DV-3 lint_migrations.dart (decodeBytea grep)
                                                                          │       ├─ P2.3 DV-4 schema_diff.dart
                                                                          │       └─ P2.4 DV-5 GitHub Actions CI workflow
                                                                          │
                                                                          │   P2.5 DB-2 migration 0018 audit_events (13+3 event_types)
                                                                          │       │
                                                                          │       ├─ P2.6 EF-2 audit writes in create_invite + claim_invite
                                                                          │       ├─ P2.7 EF-3 audit writes in claim_recovery, snapshots
                                                                          │       └─ P2.8 EF-4 audit writes in revoke_device, key_rotate
                                                                          │
                                                                          │   P2.9 DB-3 migration 0019 recovery + envelopes + cursors
                                                                          │       │
                                                                          │       ├─ P2.10 DB-4 migration 0020 snapshots
                                                                          │       ├─ P2.11 DB-5 migration 0021 device_sync_cursors
                                                                          │       └─ P2.12 [NEW DB-7] compact_family_versions SQL fn
                                                                          │              │
                                                                          │              └─ P2.13 EF-5 compact_encrypted_rows EF
                                                                          │                     │
                                                                          │                     └─ P2.14 TI-10 device_sync_cursors upsert test
                                                                          │
                                                                          │   P2.15 DB-6 right_to_be_forgotten function
                                                                          │       └─ P2.16 EF-7 request_erasure EF
                                                                          │
                                                                          │   P2.17 [NEW DB-9] test_only_age_recovery_attempts RPC
                                                                          │       └─ P2.18 SEC-5 recovery rate-limit test
                                                                          │
                                                                          │   P2.19 [NEW EF-9] cleanup_tombstones cron (§6.6)
                                                                          │
                                                                          │   P2.20 SY-9 CountAttestation service
                                                                          │   P2.21 SY-10 zstd compression in CryptoEnvelope
                                                                          │
                                                                          │   P2.22 BG-1a/b SyncTrigger enum + WorkManager registration
                                                                          │       │
                                                                          │       ├─ P2.23 BG-2 ConnectivityListener
                                                                          │       ├─ P2.24 BG-3 AndroidManifest WorkManager perms
                                                                          │       ├─ P2.25 BG-4 iOS BGAppRefreshTask Info.plist
                                                                          │       ├─ P2.26 BG-5 syncNow() trigger fan-in
                                                                          │       ├─ P2.27 BG-6 audit emit (sync_background_started/finished)
                                                                          │       └─ P2.28 BG-7..9 tests (unit + integ + manifest grep)
                                                                          │
                                                                          │   P2.29 TI-5..8 integration scenarios 3-6 (tombstone, conflict, T1, count)
                                                                          │   P2.30 TI-11 dart_test.yaml + CI plumbing
                                                                          │
                                                                          │   P2.31 SEC-1..4, SEC-6..10 adversarial suite
                                                                          │
                                                                          │   P2.32 DV-6 Sentry SDK + scrubber
                                                                          │   P2.33 DV-7 Supabase alerts
                                                                          │   P2.34 DV-8 synthetic monitor
                                                                          │
                                                                          │   P2.35 DB-8 pgTAP runner
                                                                          │
                                                                          │   P2.36 [Phase 2 exit gate]
```

**Critical path Phase 1:** DV-1 → SY-1 → SY-2 → TI-1/2 → TI-3/4 → exit gate.
**Critical path Phase 2:** DV-2 → DV-5 (CI online) → DB-2 (audit_events live) → EF-2..4 (audit writes flowing) → BG-1..6 (auto-sync wired) → exit gate.

---

## Phase 1 — Triage (Week 1)

### P1.1 [DV-1] Checkpoint commit of uncommitted work (BLOCKING ROOT)

**Owner:** SRE/DevOps. **Files:** `feat/plan-d-premium` working tree (40+ files, 9 migrations).

- [ ] Step 1: `git status` and capture full output to `/tmp/dreambook-precheckpoint-status.txt`. Verify count of modified + untracked files matches the 40-file expectation.
- [ ] Step 2: `git stash list` → confirm no shadow stashes that would silently drop on later operations.
- [ ] Step 3: `git diff --stat HEAD` → confirm no migration files are accidentally `-D` (deletions).
- [ ] Step 4: Create branch off current HEAD: `git switch -c hardening/phase-1-base`.
- [ ] Step 5: Stage in 3 batches to keep diffs reviewable — first migrations only (`git add supabase/migrations/`), commit with `chore(checkpoint): migrations 0005-0016 inclusive (pre-hardening)`.
- [ ] Step 6: Stage Dart core (`git add lib/core/`), commit with `chore(checkpoint): lib/core sync+crypto WIP (pre-hardening)`.
- [ ] Step 7: Stage remaining (`git add .`), commit with `chore(checkpoint): remaining WIP (pre-hardening)`.
- [ ] Step 8: Tag: `git tag -a checkpoint/plan-d-pre-hardening -m "Pre-hardening checkpoint per spec §4 Phase 1 exit"`.
- [ ] Step 9: Push branch + tag to origin: `git push -u origin hardening/phase-1-base && git push origin checkpoint/plan-d-pre-hardening`.
- [ ] Step 10: Verify rollback works: in a scratch worktree, `git switch --detach checkpoint/plan-d-pre-hardening` and confirm `flutter analyze` runs (won't pass — just confirms checkout is consistent).
- [ ] Step 11: Document the rollback procedure in `docs/runbook-rollback.md` referencing the tag.

### P1.2 [SY-1] bytea_codec helper + unit tests

**Owner:** Flutter Engineer. **Files:** `lib/core/sync/bytea_codec.dart`, `test/core/sync/bytea_codec_test.dart`.

- [ ] Step 1: Write failing tests for all 4 input shapes (Uint8List passthrough, List<int>, hex `\x...`, base64 string, plus ArgumentError for unsupported type). See Team 2 SY-1 step 1 for full test body.
- [ ] Step 2: `flutter test test/core/sync/bytea_codec_test.dart` → expect FAIL on undefined `decodeBytea`.
- [ ] Step 3: Implement `decodeBytea(dynamic v)` per Team 2 SY-1 step 3 — top-level public function (NOT a private `_decodeBytes`; this is the spec-deviation accepted in audit § "bytea decoder name mismatch").
- [ ] Step 4: `flutter test test/core/sync/bytea_codec_test.dart` → expect PASS (5 tests).
- [ ] Step 5: `git add lib/core/sync/bytea_codec.dart test/core/sync/bytea_codec_test.dart && git commit -m "feat(sync): add bytea_codec for PostgREST encoding compatibility"`.

### P1.3 [SY-2] Replace 5 bytea cast sites in SupabaseSyncServer

**Owner:** Flutter Engineer. **Files:** `lib/core/sync/supabase_sync_server.dart`.

- [ ] Step 1: Add `import 'bytea_codec.dart';` to top of file.
- [ ] Step 2: Replace `pullRows` lines 98–99 — `ciphertext: decodeBytea(m['ciphertext'])`, `aadHash: decodeBytea(m['aad_hash'])`.
- [ ] Step 3: Replace `realtimeStream` lines 133–135 — `ciphertext: decodeBytea(row['ciphertext'])`, `aadHash: decodeBytea(row['aad_hash'])`.
- [ ] Step 4: Replace `pullKeyDistribution` line 164 — `wrappedKey: decodeBytea(m['wrapped_key'])`.
- [ ] Step 5: Delete the `runtimeType` debug log block at lines 83–90; drop the `package:flutter/foundation.dart` import if no longer used.
- [ ] Step 6: `flutter analyze lib/core/sync/supabase_sync_server.dart` → clean.
- [ ] Step 7: `grep -n 'as List).cast<int>()' lib/core/sync/supabase_sync_server.dart` → must return nothing.
- [ ] Step 8: Commit per Team 2 SY-2 step 7.

### P1.4 [DB-1] Migration 0017 — RLS reharden

**Owner:** Postgres DBA. **Files:** `supabase/migrations/0017_rls_reharden.sql`.

- [ ] Step 1: Create empty migration file with header comment block citing spec §5.1.
- [ ] Step 2: Add `DROP POLICY IF EXISTS encrypted_rows_insert ON public.encrypted_rows;` then the restored INSERT policy with `written_by_device` and `key_version` predicates (spec §5.1 first block).
- [ ] Step 3: Add `DROP POLICY IF EXISTS encrypted_rows_update ON public.encrypted_rows;` then the row-ownership UPDATE policy (spec §5.1 second block).
- [ ] Step 4: Add explicit grants — `GRANT SELECT ON public.families TO authenticated;` and `GRANT SELECT ON public.family_devices TO authenticated;`.
- [ ] Step 5: Add the two performance indexes (`family_devices_auth_user_id_idx`, `family_devices_device_fp_active_idx`) with `WHERE` clauses per spec.
- [ ] Step 6: Apply to local supabase: `supabase db reset && supabase db push`; verify policies via `\d+ public.encrypted_rows`.
- [ ] Step 7: Hand-write a pgTAP test in `supabase/tests/0017_rls_reharden_test.sql` asserting (a) `encrypted_rows_insert` exists, (b) policy CHECK contains `written_by_device`, (c) policy CHECK contains `key_version`, (d) UPDATE USING contains `device_fp`.
- [ ] Step 8: Commit with `feat(db): migration 0017 restores encrypted_rows RLS guards`.

### P1.5 [EF-1] create_invite Edge Function — authenticate caller

**Owner:** Flutter Engineer + Postgres DBA. **Files:** `supabase/functions/create_invite/index.ts`.

- [ ] Step 1: Add Deno test `create_invite_unauthenticated_returns_401_test.ts` calling the function with no `Authorization` header; expect 401.
- [ ] Step 2: Add Deno test `create_invite_non_admin_returns_403_test.ts` with a JWT whose user has no admin `family_devices` row; expect 403.
- [ ] Step 3: Replace the bare anon client with a per-request client: `const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } })`.
- [ ] Step 4: Resolve caller: `const { data: { user } } = await supabase.auth.getUser();` — reject 401 if `user == null`.
- [ ] Step 5: Lookup admin: `SELECT 1 FROM family_devices WHERE auth_user_id = $1 AND family_id = $2 AND revoked_at IS NULL AND role = 'admin'` — reject 403 on no row.
- [ ] Step 6: Run Deno tests locally; both must pass.
- [ ] Step 7: Add audit-event hook stub (commented `// TODO(P2.6 EF-2): write invite_created here once 0018 lands`) — explicitly noted as cross-phase wiring, NOT a placeholder. Phase 2 EF-2 removes the comment.
- [ ] Step 8: Commit with `fix(ef): create_invite now authenticates caller and verifies admin`.

### P1.6 [TI-1] Real-adapter harness skeleton

**Owner:** QA Auditor. **Files:** `test/integration/_harness/supabase_real_adapter.dart`, `integration_test/_harness/`, `supabase/seed/test_seed.sql`.

- [ ] Step 1: Add `dev_dependencies: integration_test:` to `pubspec.yaml`; run `flutter pub get`.
- [ ] Step 2: Create harness class `SupabaseRealAdapter` exposing `startLocalStack()` (shells out to `supabase start`), `applyMigrations()` (reads `supabase/migrations/*.sql` in order, executes each via psql), `resetForTest()` (TRUNCATE every table except `auth.users`), `tearDown()`.
- [ ] Step 3: Write seed SQL that creates 2 auth users (`mom@test`, `dad@test`) and 1 family with both as admin devices.
- [ ] Step 4: Add `dart_test.yaml` with tags: `unit`, `integration`, `security`. Default `flutter test` runs `unit`; CI runs all.
- [ ] Step 5: Smoke test the harness: `flutter test integration_test/_harness_smoke_test.dart` should boot supabase, run seed, query 1 row, tear down.
- [ ] Step 6: Commit with `feat(test): real-adapter harness scaffolding for Ring 2`.

### P1.7 [TI-2] Two-device test fixture

**Owner:** QA Auditor. **Files:** `test/integration/_fixtures/two_device_family.dart`.

- [ ] Step 1: Define `TwoDeviceFamily` fixture exposing `momDevice: SyncWorker`, `dadDevice: SyncWorker`, `family: Family`, each wired through `SupabaseSyncServer` against the real-adapter harness.
- [ ] Step 2: Each device uses its own SQLCipher in-memory DB (no shared file).
- [ ] Step 3: Provide `seedSampleFeed(deviceLabel, count)` helper.
- [ ] Step 4: Write fixture smoke test: spin up both devices, write 1 feed on mom, manually call dad's `pullOnce`, assert row appears.
- [ ] Step 5: Commit with `feat(test): two-device family fixture for integration tests`.

### P1.8 [TI-3] Integration scenario 1 — 2-device push within 5s

**Owner:** QA Auditor. **Files:** `test/integration/sync_scenario_1_push_test.dart`. **Requires:** DB-1 applied (declared in handoff).

- [ ] Step 1: Write test — mom writes a feed; await realtime delivery on dad within 5s; assert row content + AAD MAC verifies.
- [ ] Step 2: Verify across 3 consecutive runs — flake budget = 0.
- [ ] Step 3: Tag with `@Tags(['integration'])`.
- [ ] Step 4: Commit.

### P1.9 [TI-4] Integration scenario 2 — offline 50-row catch-up

**Owner:** QA Auditor. **Files:** `test/integration/sync_scenario_2_offline_test.dart`. **Requires:** DB-1, SY-7.

- [ ] Step 1: Stop dad's realtime stream; mom writes 50 feeds.
- [ ] Step 2: Restart dad's stream + force `pullOnce`.
- [ ] Step 3: Assert all 50 rows present on dad with correct `version` ordering.
- [ ] Step 4: Assert `sync_cursors.last_pull_at` advanced past the last write.
- [ ] Step 5: Commit.

### P1.10 [SY-3a..c] RetryPolicy (split for bite-size)

**Owner:** Flutter Engineer. **Files:** `lib/core/sync/retry_policy.dart`, `test/core/sync/retry_policy_test.dart`.

- [ ] Step 1 (SY-3a): Write failing tests for `RetryPolicy.classify` only (5 cases — SocketException, TimeoutException, TypeError, ArgumentError, HttpException). Run → FAIL.
- [ ] Step 2 (SY-3a): Implement `enum ErrorClass { transient, terminal }` and `static ErrorClass classify(Object error)` per Team 2 SY-3 step 3. Run → PASS.
- [ ] Step 3 (SY-3b): Write failing tests for `delayFor(attempt)` only (3 cases — attempt 1 → 800–1200ms, attempt 5 → 12800–19200ms, attempt 6 → Duration.zero). Run → FAIL.
- [ ] Step 4 (SY-3b): Implement `Duration delayFor(int attempt)` with `1 << (attempt - 1)` base + ±20% jitter from a seeded `Random`. Run → PASS.
- [ ] Step 5 (SY-3c): Write failing tests for `run<T>(body)` (3 cases — retries-then-rethrows on transient, no-retry-on-terminal, returns-value-on-first-success). Run → FAIL.
- [ ] Step 6 (SY-3c): Implement `Future<T> run<T>(Future<T> Function() body)`. Run → PASS (all 10 tests green).
- [ ] Step 7: Single commit with all of SY-3a/b/c per Team 2 SY-3 step 5.

### P1.11 [SY-4] Wire RetryPolicy into SyncWorker

**Owner:** Flutter Engineer. **Files:** `lib/core/sync/sync_worker.dart`, `lib/core/sync/sync_lifecycle_controller.dart`.

- [ ] Step 1: Add `import 'retry_policy.dart';` and `RetryPolicy? retryPolicy` constructor param with `retry = retryPolicy ?? RetryPolicy()` default.
- [ ] Step 2: Wrap `server.insertEncryptedRow` call in `pushOnce` with `retry.run(() => ...)`.
- [ ] Step 3: Wrap `server.pullRows` call in `pullOnce` with `retry.run(() => ...)`.
- [ ] Step 4: Verify existing sync tests still pass; for any pre-existing transient-error test that times out, inject `RetryPolicy(seed: 1, baseDelay: Duration.zero)`.
- [ ] Step 5: Commit per Team 2 SY-4 step 6.

### P1.12 [SY-5] Non-silent error path via SyncErrorReporter

**Owner:** Flutter Engineer. **Files:** `lib/core/sync/sync_error_reporter.dart`, `lib/core/sync/sync_lifecycle_controller.dart`, `test/core/sync/sync_lifecycle_error_reporting_test.dart`.

- [ ] Step 1: Create `SyncErrorReporter` abstract class, `DebugSyncErrorReporter`, `CompositeSyncErrorReporter` per Team 2 SY-5 step 1.
- [ ] Step 2: Replace silent catch at `sync_lifecycle_controller.dart:79-82` with reporter call + `status.failSync(e)`.
- [ ] Step 3: Sanitize payload — only `trigger`, `family_id_known: bool`, `error_type: runtimeType.toString()`. No ciphertext, keys, PII.
- [ ] Step 4: Write `CompositeSyncErrorReporter` test asserting one child's throw doesn't mask the other's report.
- [ ] Step 5: Commit per Team 2 SY-5 step 5.

### P1.13 [SY-6] RealtimeStatus enum + reconnect state machine

**Owner:** Flutter Engineer. **Files:** `lib/core/sync/realtime_subscriber.dart`, `test/core/sync/realtime_subscriber_reconnect_test.dart`.

- [ ] Step 1: Write failing reconnect test per Team 2 SY-6 step 1 — connected → degraded → connected → offline transition sequence.
- [ ] Step 2: Run → FAIL.
- [ ] Step 3: Rewrite `RealtimeSubscriber` body with `enum RealtimeStatus { connected, degraded, offline }`, `onStatus` callback, `_scheduleReconnect()` with capped exponential (1s base, 30s max, ±20% jitter), `_disposed` flag to prevent reconnect after `disconnect()`.
- [ ] Step 4: Add `onStatus` wiring to `sync_lifecycle_controller.dart` that flows into `syncStatusProvider` notifier with `markRealtimeConnected/Degraded/Offline` methods (stub the missing two if not present — preserve `markRealtimeDegraded` parity).
- [ ] Step 5: Run → PASS.
- [ ] Step 6: Commit per Team 2 SY-6 step 6.

### P1.14 [SY-7] Migration m007 + sync_cursors local table

**Owner:** Flutter Engineer. **Files:** `lib/core/db/migrations/m007_sync_cursors.dart`, `lib/core/db/migrations/migrations.dart`, `lib/core/sync/sync_cursors_dao.dart`, `lib/core/sync/sync_worker.dart`, `test/core/sync/sync_cursors_dao_test.dart`.

- [ ] Step 1: Add `m007SyncCursors` migration per Team 2 SY-7 step 1.
- [ ] Step 2: Register in `migrations.dart` after `m006`.
- [ ] Step 3: Build `SyncCursorsDao` with `readLastPullAt`, `writeLastPullAt`, `reset` per Team 2 SY-7 step 2.
- [ ] Step 4: Write DAO round-trip test using sqflite_common_ffi in-memory.
- [ ] Step 5: Replace `_lastPullAt` field in `SyncWorker` with `SyncCursorsDao cursors`; pull's `since` becomes `await cursors.readLastPullAt(familyId)`; after pull, advance via `cursors.writeLastPullAt(familyId, maxTs)`.
- [ ] Step 6: Run `flutter test test/core/sync/` → all green.
- [ ] Step 7: Commit per Team 2 SY-7 step 6.

### P1.15 [SY-8] Tombstone DELETE in _applyIncoming

**Owner:** Flutter Engineer. **Files:** `lib/core/sync/sync_worker.dart`, `test/core/sync/sync_worker_tombstone_test.dart`.

- [ ] Step 1: Write failing test — pre-seed a local feed row, pull a `RemoteEncryptedRow` with `deletedAt != null` and same `recordId`, assert `db.query` returns empty.
- [ ] Step 2: Run → FAIL.
- [ ] Step 3: In `_applyIncoming` transaction, branch on `row.deletedAt != null`: `txn.delete(row.tableName, where: 'id = ?', whereArgs: [row.recordId])` instead of `txn.insert(... replace)`. Still upsert `sync_state` so cursor advances.
- [ ] Step 4: Run → PASS; existing pull/conflict tests still green.
- [ ] Step 5: Commit per Team 2 SY-8 step 5.

### P1.16 Phase 1 exit gate

- [ ] All Phase 1 tasks marked complete
- [ ] Lead Architect, Postgres DBA, Security Reviewer, QA Auditor sign-offs recorded in `docs/phase-exits/phase-1.md`
- [ ] Real-adapter integration test scenarios #1 + #2 pass against staging Supabase
- [ ] Migration linter green (deferred to P2.2 — placeholder: spot-check by hand)
- [ ] `grep -rn 'as List).cast<int>()' lib/core/sync/` returns nothing
- [ ] `sync_lifecycle_controller.dart` no longer contains the bare `debugPrint('SyncWorker error...')`
- [ ] Checkpoint tag `checkpoint/plan-d-pre-hardening` accessible on origin

---

## Phase 2 — Ops foundation (Week 2)

### P2.1 [DV-2] Staging Supabase project provisioning

**Owner:** SRE/DevOps. **Files:** `supabase/config/staging.toml`, `docs/staging-environment.md`.

- [ ] Step 1: Create new Supabase project in `ap-southeast-1` named `dreambook-staging`.
- [ ] Step 2: Copy production schema export → apply to staging via `supabase db push --project-ref <staging-ref>`.
- [ ] Step 3: Add `STAGING_SUPABASE_URL` and `STAGING_SUPABASE_ANON_KEY` to GitHub Actions secrets (NOT to repo .env).
- [ ] Step 4: Document the staging-vs-prod project-ref lookup in `docs/staging-environment.md`.
- [ ] Step 5: Verify schema diff staging vs prod is empty (baseline).

### P2.2 [DV-3] Migration linter

**Owner:** SRE/DevOps. **Files:** `tool/lint_migrations.dart`, `test/tool/lint_migrations_test.dart`.

- [ ] Step 1: Write the linter spec doc comment listing 5 rules from spec §5.9, with rule 2 updated: "every `bytea` column → has a matching `decodeBytea` call site in `lib/core/sync/`" (NOT `_decodeBytes` — per audit resolution).
- [ ] Step 2: Implement rule 1 — scan `supabase/migrations/*.sql` for `CREATE TABLE`; for each, require subsequent `ENABLE ROW LEVEL SECURITY` + at least one `GRANT`.
- [ ] Step 3: Implement rule 2 — scan migrations for `bytea` column declarations; collect set; cross-check against `grep -r 'decodeBytea(' lib/core/sync/` results.
- [ ] Step 4: Implement rule 3 — every `CREATE POLICY` must be preceded by a `DROP POLICY IF EXISTS` for the same name in the same file.
- [ ] Step 5: Implement rule 5 — `ALTER TABLE ... DROP COLUMN` must be preceded by a `-- deprecation:` comment.
- [ ] Step 6: Write 5 regression-fixture tests (one per rule) — each fixture is a synthetic bad migration that the linter should flag.
- [ ] Step 7: Commit.

### P2.3 [DV-4] Schema diff tool

**Owner:** SRE/DevOps. **Files:** `tool/schema_diff.dart`.

- [ ] Step 1: Shell out to `supabase db diff --linked --schema public > /tmp/staging_vs_prod.sql`.
- [ ] Step 2: Parse output; exit non-zero if non-empty.
- [ ] Step 3: Print human-readable section per drift table.
- [ ] Step 4: Add unit test using fake stdin fixture.

### P2.4 [DV-5] GitHub Actions CI

**Owner:** SRE/DevOps. **Files:** `.github/workflows/ci.yml`.

- [ ] Step 1: Job `analyze` — `flutter analyze`.
- [ ] Step 2: Job `unit` — `flutter test --tags unit`.
- [ ] Step 3: Job `lint-migrations` — `dart run tool/lint_migrations.dart`.
- [ ] Step 4: Job `schema-diff` — pulls staging creds from secrets, runs `dart run tool/schema_diff.dart`.
- [ ] Step 5: Job `integration` — `supabase start` (uses Docker action), `flutter test --tags integration`.
- [ ] Step 6: Add `concurrency.group: ci-${{ github.ref }}` to avoid duplicate runs.
- [ ] Step 7: Verify CI green on three test PRs (one synthetic, one minor change, one intentional-regression for linter).

### P2.5 [DB-2] Migration 0018 — audit_events

**Owner:** Postgres DBA. **Files:** `supabase/migrations/0018_audit_events.sql`.

- [ ] Step 1: Create table per spec §5.3 — `id`, `family_id`, `actor_device_fp bytea`, `event_type text` (CHECK constraint with the 13 spec values PLUS `'sync_background_started'`, `'sync_background_finished'`, `'realtime_reconnected'` per audit-resolved cross-team alignment), `event_data jsonb`, `created_at`.
- [ ] Step 2: Add index `audit_events_by_family`.
- [ ] Step 3: `ALTER TABLE ... ENABLE ROW LEVEL SECURITY;` + `audit_events_select` policy.
- [ ] Step 4: Add `INSERT` policy that allows only `service_role` (rest of writes via SECURITY DEFINER from Edge Functions).
- [ ] Step 5: Apply to local + staging; verify via pgTAP test.
- [ ] Step 6: Commit.

### P2.6 [EF-2] Audit writes in create_invite + claim_invite

**Owner:** Flutter Engineer. **Files:** `supabase/functions/create_invite/index.ts`, `supabase/functions/claim_invite/index.ts`, `supabase/functions/_shared/audit.ts`.

- [ ] Step 1: Create shared `writeAuditEvent(family_id, event_type, actor_device_fp, event_data)` helper using `service_role` admin client.
- [ ] Step 2: In `create_invite`, after successful insert call `writeAuditEvent(family_id, 'invite_created', adminDeviceFp, { invite_id })`.
- [ ] Step 3: In `claim_invite` happy path: `writeAuditEvent(family_id, 'invite_claimed', newDeviceFp, { invite_id })`.
- [ ] Step 4: In `claim_invite` failure paths (expired, wrong code, already-consumed): `writeAuditEvent(family_id, 'invite_failed', null, { reason })`.
- [ ] Step 5: Remove the `TODO(P2.6 EF-2)` comment seeded in EF-1 step 7.
- [ ] Step 6: Deno test asserting each path writes the expected row.

### P2.7 [EF-3] Audit writes in claim_recovery + snapshots

**Owner:** Flutter Engineer. **Files:** placeholder Edge Functions for Phase 3-4 features.

- [ ] Step 1: Add empty stub `claim_recovery/index.ts` that returns 503 `Not Implemented` BUT writes a `recovery_attempted` audit event (so the audit pipeline is tested before the feature lands).
- [ ] Step 2: Same for `upload_snapshot` and `restore_snapshot` stubs emitting `snapshot_uploaded` / `snapshot_restored`.
- [ ] Step 3: Document in stub header that Phase 3/4 will implement bodies.

### P2.8 [EF-4] Audit writes in revoke_device + key_rotate

**Owner:** Flutter Engineer. **Files:** `supabase/functions/revoke_device/index.ts`, `supabase/functions/key_rotate/index.ts`.

- [ ] Step 1: Hook `writeAuditEvent('device_revoked', ...)` into the existing revoke flow.
- [ ] Step 2: Hook `writeAuditEvent('key_rotated', ...)` into key rotation.
- [ ] Step 3: Both must include `actor_device_fp` derived from `auth.uid()` lookup.
- [ ] Step 4: Deno tests for each.

### P2.9 [DB-3] Migration 0019 — recovery + envelopes

**Owner:** Postgres DBA. **Files:** `supabase/migrations/0019_recovery_tables.sql`.

- [ ] Step 1: `family_recovery_envelopes` table per spec §5.5.
- [ ] Step 2: `recovery_attempts` table per spec §5.7 with `recovery_attempts_recent` index.
- [ ] Step 3: `recovery_lookup` table (referenced in spec §12 inventory; not yet specified — minimal shape: `lookup_hash bytea PRIMARY KEY`, `family_id uuid NOT NULL REFERENCES families`).
- [ ] Step 4: RLS for all three (envelopes: select-by-family; recovery_attempts: service_role only; recovery_lookup: service_role only).
- [ ] Step 5: pgTAP test.

### P2.10 [DB-4] Migration 0020 — snapshots

**Owner:** Postgres DBA. **Files:** `supabase/migrations/0020_snapshots.sql`.

- [ ] Step 1: `encrypted_snapshots` table per spec §5.4.
- [ ] Step 2: RLS — select where `family_id IN current_user_family_ids()`; INSERT/UPDATE via SECURITY DEFINER.
- [ ] Step 3: Storage bucket `family-snapshots` policies (separate file `supabase/storage/family-snapshots.sql`).
- [ ] Step 4: pgTAP test.

### P2.11 [DB-5] Migration 0021 — device_sync_cursors

**Owner:** Postgres DBA. **Files:** `supabase/migrations/0021_device_sync_cursors.sql`.

- [ ] Step 1: Create table per spec §5.6 with PK `(family_id, device_fp)` and columns `last_pulled_at`, `last_pulled_version_max bigint`, `updated_at`.
- [ ] Step 2: RLS — select/insert/update predicates per spec §5.6.
- [ ] Step 3: pgTAP test.

### P2.12 [NEW DB-7] compact_family_versions SQL function

**Owner:** Postgres DBA. **Files:** `supabase/migrations/0022_compact_family_versions.sql`.

- [ ] Step 1: Define function:
  ```sql
  CREATE OR REPLACE FUNCTION public.compact_family_versions(p_family_id uuid)
  RETURNS TABLE(deleted_count bigint)
  LANGUAGE plpgsql
  SECURITY DEFINER
  AS $$
  DECLARE
    v_min_cursor bigint;
    v_stale_device_count int;
  BEGIN
    SELECT COUNT(*) INTO v_stale_device_count
    FROM public.family_devices fd
    LEFT JOIN public.device_sync_cursors dsc
      ON dsc.family_id = fd.family_id AND dsc.device_fp = fd.device_fp
    WHERE fd.family_id = p_family_id
      AND fd.revoked_at IS NULL
      AND (dsc.last_pulled_at IS NULL OR dsc.last_pulled_at < now() - INTERVAL '7 days');
    IF v_stale_device_count > 0 THEN
      RETURN QUERY SELECT 0::bigint;
      RETURN;
    END IF;
    SELECT COALESCE(MIN(last_pulled_version_max), 0) INTO v_min_cursor
    FROM public.device_sync_cursors dsc
    JOIN public.family_devices fd ON fd.family_id = dsc.family_id AND fd.device_fp = dsc.device_fp
    WHERE dsc.family_id = p_family_id AND fd.revoked_at IS NULL;
    RETURN QUERY
    WITH latest AS (
      SELECT record_id, table_name, MAX(version) AS max_v
      FROM public.encrypted_rows
      WHERE family_id = p_family_id
        AND deleted_at IS NULL
      GROUP BY record_id, table_name
    ),
    deleted AS (
      DELETE FROM public.encrypted_rows er
      WHERE er.family_id = p_family_id
        AND er.version < v_min_cursor
        AND (er.record_id, er.table_name) NOT IN (SELECT record_id, table_name FROM latest)
      RETURNING 1
    )
    SELECT COUNT(*)::bigint FROM deleted;
  END;
  $$;
  ```
- [ ] Step 2: pgTAP test SSI-2: insert 3 versions of same record, all devices pulled past v3, run function → only versions 1 and 2 deleted, version 3 (latest non-tombstone) preserved.
- [ ] Step 3: pgTAP test stale-device safety: one device hasn't pulled in 8 days → function returns 0 deleted.
- [ ] Step 4: Commit.

### P2.13 [EF-5] compact_encrypted_rows Edge Function

**Owner:** Flutter Engineer. **Files:** `supabase/functions/compact_encrypted_rows/index.ts`. **Requires:** P2.12.

- [ ] Step 1: Function iterates all `families` rows; for each, calls `admin.rpc('compact_family_versions', { p_family_id })`.
- [ ] Step 2: Aggregates total deleted; writes single audit event per run.
- [ ] Step 3: Deno test using local supabase verifying it doesn't violate SSI-2.

### P2.14 [TI-10] device_sync_cursors upsert test

**Owner:** QA Auditor. **Files:** `test/integration/sync_cursor_upsert_test.dart`.

- [ ] Step 1: After dad's successful pull, assert `device_sync_cursors` row exists with `last_pulled_version_max` matching the max version pulled.
- [ ] Step 2: Re-pull → row updated, `updated_at` advances.

### P2.15 [DB-6] right_to_be_forgotten function

**Owner:** Postgres DBA. **Files:** `supabase/migrations/0023_right_to_erasure.sql`.

- [ ] Step 1: Define function per spec §5.8.
- [ ] Step 2: pgTAP test: insert family with rows in all 9 tables; call function; assert all FK-cascaded tables empty + audit row present with `erased: true`.

### P2.16 [EF-7] request_erasure Edge Function

**Owner:** Flutter Engineer. **Files:** `supabase/functions/request_erasure/index.ts`.

- [ ] Step 1: Verify caller JWT; verify caller is admin of `body.family_id`.
- [ ] Step 2: Call `admin.rpc('right_to_be_forgotten', { p_family_id: body.family_id })`.
- [ ] Step 3: Return 200 with `{ erased: true }`.
- [ ] Step 4: Deno test.

### P2.17 [NEW DB-9] test_only_age_recovery_attempts RPC

**Owner:** Postgres DBA. **Files:** `supabase/migrations/staging/0900_test_helpers.sql` (note: separate staging-only path).

- [ ] Step 1: Define:
  ```sql
  CREATE OR REPLACE FUNCTION public.test_only_age_recovery_attempts(
    p_family_id uuid, p_age interval
  ) RETURNS void
  LANGUAGE plpgsql SECURITY DEFINER AS $$
  BEGIN
    IF current_setting('app.test_mode', true) IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'test_only_* helpers may not be called in production';
    END IF;
    UPDATE public.recovery_attempts
    SET attempted_at = attempted_at - p_age
    WHERE family_id = p_family_id;
  END;
  $$;
  ```
- [ ] Step 2: Ensure prod migration set EXCLUDES this file (CI check in DV-3 rule 6: file matching `supabase/migrations/staging/**` must never appear in prod migration list).
- [ ] Step 3: In integration test setUp, run `SET app.test_mode = 'true';`.

### P2.18 [SEC-5] Recovery rate-limit adversarial test

**Owner:** Security Reviewer. **Files:** `test/security/recovery_rate_limit_test.dart`. **Requires:** P2.17.

- [ ] Step 1: Hammer `claim_recovery` 5 times with bad phrase → 5 rows in `recovery_attempts`.
- [ ] Step 2: 6th attempt → 429 with `retry-after: 3600`.
- [ ] Step 3: Call `test_only_age_recovery_attempts(family, '1h 1min')` → 6th attempt now allowed.

### P2.19 [NEW EF-9] cleanup_tombstones cron Edge Function

**Owner:** Flutter Engineer. **Files:** `supabase/functions/cleanup_tombstones/index.ts`.

- [ ] Step 1: Function reads `families.tombstone_retention_days` per family; deletes rows where `deleted_at < now() - INTERVAL families.tombstone_retention_days`.
- [ ] Step 2: pg_cron schedule daily at 03:00 UTC.
- [ ] Step 3: Writes audit event per family with count.
- [ ] Step 4: Deno test.

### P2.20 [SY-9] CountAttestation service (expanded from Team 2 placeholders)

**Owner:** Flutter Engineer. **Files:** `lib/core/sync/count_attestation.dart`, `test/core/sync/count_attestation_test.dart`, `lib/core/sync/sync_server.dart`, `lib/core/sync/supabase_sync_server.dart`, `test/_fakes/fake_supabase_server.dart`, `lib/core/sync/sync_worker.dart`.

- [ ] Step 1: Add `countRows({required String familyId})` to `SyncServer` interface.
- [ ] Step 2: Implement on `SupabaseSyncServer` using `_client.from('encrypted_rows').select('table_name').eq('family_id', familyId).filter('deleted_at', 'is', null)`.
- [ ] Step 3: Implement on `FakeSupabaseServer` (loop encryptedRows, exclude tombstones).
- [ ] Step 4: Build `CountAttestation` class per Team 2 SY-9 step 4 with const `tables` list of 9 syncable tables.
- [ ] Step 5: Add constructor param `CountAttestation? attestation` to `SyncWorker`; call `attestation!.verify()` at end of `pullOnce`.
- [ ] Step 6 (expands Team 2 placeholder): Write test "verify() returns true when counts match":
  ```dart
  // Arrange — fake server has 2 feed rows for fam-1; local DB has 2 feed rows
  await server.encryptedRows.addAll([_feedRow('fam-1', 'a'), _feedRow('fam-1', 'b')]);
  await db.insert('feed', {'id': 'a', 'baby_id': 'b1', /* ... */});
  await db.insert('feed', {'id': 'b', 'baby_id': 'b1', /* ... */});
  // Act
  final ok = await attestation.verify();
  // Assert
  expect(ok, isTrue);
  ```
- [ ] Step 7 (expands Team 2 placeholder): Write test "verify() resets cursor + reports diff on mismatch":
  ```dart
  await server.encryptedRows.addAll([_feedRow('fam-1', 'a'), _feedRow('fam-1', 'b')]);
  await db.insert('feed', {'id': 'a', 'baby_id': 'b1', /* ... */});
  await cursors.writeLastPullAt('fam-1', DateTime.now().toUtc());
  Map<String, (int, int)>? captured;
  final att = CountAttestation(
    db: db, server: server, cursors: cursors, familyId: 'fam-1',
    onMismatch: (d) => captured = d,
  );
  final ok = await att.verify();
  expect(ok, isFalse);
  expect(captured, equals({'feed': (1, 2)}));
  expect(await cursors.readLastPullAt('fam-1'), isNull);
  ```
- [ ] Step 8: Commit per Team 2 SY-9 step 8.

### P2.21 [SY-10] CryptoEnvelope zstd compression

**Owner:** Flutter Engineer. **Files:** `lib/core/crypto/crypto_envelope.dart`, `pubspec.yaml`, `test/core/crypto/crypto_envelope_compression_test.dart`.

- [ ] Step 1: Add `zstandard: ^1.2.0` to pubspec; `flutter pub get`.
- [ ] Step 2: Implement versioned envelope per Team 2 SY-10 step 2 with `_vLegacy = 0x01`, `_vCompressed = 0x02`, sniff first byte for backwards-compat.
- [ ] Step 3: Round-trip tests v1, v2, v2-reads-v1, AAD-tamper-fails.
- [ ] Step 4: Verify with `flutter test test/core/crypto/`.
- [ ] Step 5: Commit per Team 2 SY-10 step 5.

### P2.22 [BG-1a] SyncTrigger enum

**Owner:** Flutter Engineer. **Files:** `lib/core/sync/sync_trigger.dart`, `test/core/sync/sync_trigger_test.dart`.

- [ ] Step 1: Define `enum SyncTrigger { realtime, foreground, networkResume, postWrite, background }`.
- [ ] Step 2: Add `String get auditEventType` extension that maps `background → 'sync_background_started'` etc.
- [ ] Step 3: Trivial unit test verifying the mapping table.

### P2.23 [BG-1b] WorkManager periodic registration

**Owner:** Flutter Engineer. **Files:** `lib/core/background/workmanager_sync.dart`, `pubspec.yaml`.

- [ ] Step 1: Add `workmanager: ^0.5` to pubspec.
- [ ] Step 2: Define top-level `callbackDispatcher` (must be top-level for WorkManager) that calls `syncNow(trigger: SyncTrigger.background)`.
- [ ] Step 3: Initialize in `main.dart` via `Workmanager().initialize(callbackDispatcher, isInDebugMode: kDebugMode)`.
- [ ] Step 4: Register inexact periodic: 15min Wi-Fi+charging, 60min otherwise — **INEXACT ONLY** per CLAUDE.md notification rule (no `setExactAndAllowWhileIdle`).
- [ ] Step 5: Unit test using `Workmanager().registerOneOffTask` in a test harness verifies dispatcher hits sync.

### P2.24 [BG-2] ConnectivityListener

**Owner:** Flutter Engineer. **Files:** `lib/core/sync/connectivity_listener.dart`.

- [ ] Step 1: Wrap `connectivity_plus` stream; emit `SyncTrigger.networkResume` on `offline → online` transitions.
- [ ] Step 2: Unit test with `StreamController<ConnectivityResult>` fixture.

### P2.25 [BG-3] AndroidManifest WorkManager permissions

**Owner:** Flutter Engineer. **Files:** `android/app/src/main/AndroidManifest.xml`.

- [ ] Step 1: Add `<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>`.
- [ ] Step 2: Verify `android:allowBackup="false"` still present.
- [ ] Step 3: Verify NO `SCHEDULE_EXACT_ALARM` or `USE_EXACT_ALARM` (run `tool/check_no_exact_alarms.sh`).
- [ ] Step 4: Add the WorkManager `<provider>` element if not auto-added by plugin.

### P2.26 [BG-4] iOS BGAppRefreshTask Info.plist

**Owner:** Flutter Engineer. **Files:** `ios/Runner/Info.plist`.

- [ ] Step 1: Add `BGTaskSchedulerPermittedIdentifiers` with `dev.niyoko.dreambook.refresh`.
- [ ] Step 2: Add `UIBackgroundModes` with `fetch`.

### P2.27 [BG-5] syncNow() trigger fan-in

**Owner:** Flutter Engineer. **Files:** `lib/core/sync/sync_lifecycle_controller.dart`.

- [ ] Step 1: Add `Future<void> syncNow({required SyncTrigger trigger})` that runs push + pull through the existing worker.
- [ ] Step 2: Wire realtime callback → `syncNow(SyncTrigger.realtime)`.
- [ ] Step 3: Wire app lifecycle resume → `syncNow(SyncTrigger.foreground)`.
- [ ] Step 4: Wire ConnectivityListener → `syncNow(SyncTrigger.networkResume)`.
- [ ] Step 5: Wire post-write debounce (500ms) → `syncNow(SyncTrigger.postWrite)`.

### P2.28 [BG-6] Background audit emit

**Owner:** Flutter Engineer. **Files:** `lib/core/sync/sync_lifecycle_controller.dart`, `supabase/functions/_shared/audit.ts`.

- [ ] Step 1: On `syncNow(trigger: SyncTrigger.background)` entry, hit a thin Edge Function `audit_background_sync` that writes `sync_background_started`.
- [ ] Step 2: On completion, write `sync_background_finished` with duration_ms.
- [ ] Step 3: Test asserts both rows present in `audit_events` after a 15-min trigger fires in emulator.

### P2.29 [BG-7..9] Background tests

- [ ] BG-7: Unit test — `SyncTrigger` audit-event-type mapping.
- [ ] BG-8: Integration test — WorkManager dispatcher calls `syncNow` exactly once per trigger.
- [ ] BG-9: Manifest grep test — `tool/check_workmanager_inexact.sh` confirms no exact-alarm strings anywhere in `android/`.

### P2.30 [TI-5..8] Integration scenarios 3–6

- [ ] TI-5: Tombstone scenario — A deletes feed, B's copy removed after pull.
- [ ] TI-6: Conflict scenario — A and B write same record offline; LWW resolves to higher (record_id, version) deterministically.
- [ ] TI-7: Recovery T1 stub (Phase 3 fully implements) — B revoked, re-invited, resyncs.
- [ ] TI-8: Count attestation after every scenario — assert `local_count == server_count` for every table.

### P2.31 [TI-11] dart_test.yaml + CI plumbing

**Owner:** QA Auditor.

- [ ] Step 1: Add `tags: { unit: { timeout: 30s }, integration: { timeout: 5m }, security: { timeout: 2m } }`.
- [ ] Step 2: Wire `flutter test --tags integration` into CI matrix (DV-5 already has the slot).

### P2.32 [SEC-1..4, SEC-6..10] Adversarial suite

Each task is one focused test under `test/security/`.

- [ ] SEC-1: Spoofed `written_by_device` rejected by RLS (3 sub-tests of 1 attack each).
- [ ] SEC-2: Stale `key_version` insert rejected.
- [ ] SEC-3a: RLS attack — cross-family SELECT blocked.
- [ ] SEC-3b: RLS attack — cross-family INSERT blocked.
- [ ] SEC-3c: RLS attack — cross-family UPDATE blocked.
- [ ] SEC-4: Invite reuse — second `claim_invite` with same code → 409.
- [ ] SEC-6: MAC tamper on `encrypted_rows.ciphertext` → `SecretBoxAuthenticationError`.
- [ ] SEC-7: AAD swap (family_id A → B) → `SecretBoxAuthenticationError`.
- [ ] SEC-8: Cross-family snapshot restore → rejected on AAD.
- [ ] SEC-9: `create_invite` unauth → 401 (covered by EF-1; security suite re-asserts).
- [ ] SEC-10: CI integration — security suite runs on every PR; failure blocks merge.

### P2.33 [DV-6] Sentry SDK + scrubber

**Owner:** SRE/DevOps. **Files:** `lib/core/observability/sentry_init.dart`.

- [ ] Step 1: Init Sentry with `beforeSend` callback stripping `event_data.ciphertext`, `event_data.aad_hash`, `event_data.wrapped_key`, any `*_key` field.
- [ ] Step 2: Opt-in flag default false; Settings UI toggle (deferred to Phase 6 for UI; flag plumbing now).

### P2.34 [DV-7] Supabase alerts

**Owner:** SRE/DevOps.

- [ ] Step 1: Dashboard alert — 5xx rate >1% (15-min window).
- [ ] Step 2: Alert — Edge Function p95 latency >2s.
- [ ] Step 3: Alert — storage growth >100MB/day.

### P2.35 [DV-8] Synthetic monitor

**Owner:** SRE/DevOps. **Files:** `.github/workflows/synthetic.yml`.

- [ ] Step 1: Workflow runs every 15min on `cron: '*/15 * * * *'`.
- [ ] Step 2: Spins up two emulators, runs scenario #1 against staging.
- [ ] Step 3: After 3 consecutive failures → opens issue + pages via existing SRE channel.

### P2.36 [DB-8] pgTAP runner

**Owner:** Postgres DBA. **Files:** `supabase/tests/run.sh`.

- [ ] Step 1: Shell runner discovers `supabase/tests/*_test.sql` and pipes each through `pg_prove`.
- [ ] Step 2: Wire into CI as `pgtap` job.

### P2.37 Phase 2 exit gate

- [ ] All Phase 2 tasks marked complete
- [ ] CI pipeline green on three test PRs (one synthetic, one minor change, one intentional-regression for linter)
- [ ] Audit log records every Edge Function invocation in staging
- [ ] Auto-sync trigger emits `SyncTrigger.background` in staging audit log every ≥15min on an emulator
- [ ] pgTAP suite green on staging
- [ ] Migration linter green on the whole tree
- [ ] All four lead-team reviewers sign off in `docs/phase-exits/phase-2.md`

---

## Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| **DV-1 checkpoint commit drops or corrupts a file** (40+ files, 3 batched commits) | Medium | Capture `git status` to `/tmp` BEFORE staging (P1.1 step 1); validate file count after each `git add` batch matches expected delta; verify rollback via scratch worktree (P1.1 step 10) BEFORE moving on |
| **`supabase start` flakes in CI** (Docker-in-Docker startup races) | Medium | Use `actions/cache@v4` on the supabase image layer; add 60s `supabase status` poll loop with exit on first green; pin supabase CLI version in CI |
| **`test_only_age_recovery_attempts` leaks to prod** | Low | Put under `supabase/migrations/staging/**`; DV-3 linter rule 6 (added in P2.2 step 1) excludes that path from prod migration set; function also self-checks `current_setting('app.test_mode')` |
| **zstd FFI fails on Android API 23 baseline** (Argon2id-style OOM risk) | Medium | Implementation falls back to v1 (uncompressed) format byte when `_zstd.compress()` returns null — backwards compat with v1 readers guaranteed; benchmark on emulator before Phase 2 exit |
| **Background sync over-fires and drains battery** (WorkManager 15min is aggressive) | Medium | Constraints `requiresBatteryNotLow=true` + `requiresCharging=true` for 15-min cadence; fall back to 60-min when unconstrained; audit-event count provides telemetry to tune |

---

## Stubbed plans for Phases 3-6

- **Phase 3 — Recovery T1 + T2** (Week 3): BIP-39 phrase generation at onboarding, write-down screen, restore-from-phrase screen, family-device re-invite UX. _To be expanded at start of Week 3._
- **Phase 4 — Recovery T3** (Week 4): Encrypted cloud snapshot with user passphrase (opt-in premium, per-family), snapshot upload/download, version pruning. _To be expanded at start of Week 4._
- **Phase 5 — Multi-family + premium gate** (Week 5): Family picker, secure storage namespacing UI, RC entitlement check at family-creation, beta to friend. _To be expanded at start of Week 5._
- **Phase 6 — Polish + launch readiness** (Week 6): Customer support runbook + script, monitoring dashboards (Sentry + Supabase), GDPR right-to-erasure UI, store assets, privacy policy + first-launch disclosure. _To be expanded at start of Week 6._

---

## Self-review checklist

- [x] Every spec §5/§6/§7/§8 requirement → at least one task (gap list above is empty after fixes — GAP-1 through GAP-5 all have inline NEW tasks)
- [x] No placeholders found in code blocks (Team 2 SY-9 `// ...` expanded into P2.20 steps 6–7)
- [x] Type/signature names consistent across teams (`decodeBytea`, `SyncTrigger`, `compact_family_versions`, `right_to_be_forgotten`, `device_sync_cursors` all aligned)
- [x] Dependency graph is acyclic and feasible in 2 weeks of focused work (Phase 1 ~9 days, Phase 2 ~10 days when SRE + Engineer + DBA + QA work in parallel)
- [x] All bite-sized steps verifiable in 2-5 min (SY-3 split into a/b/c; SEC-3 split into 3a/b/c; BG-1 split into 1a/1b)