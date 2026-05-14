# DreamBook Plan C — Sync + E2E Crypto + Caregiver Invite

**Date:** 2026-05-14
**Author:** Brainstormed with 2 senior security audits (crypto-math + mobile-hardening)
**Status:** Spec draft, pre-implementation
**Supersedes scope items in:** `2026-05-13-dreambook-design.md` §6.4 (sync), §9 (security), §11 (open questions)
**Branches:** `feat/plan-c-1-crypto` → `feat/plan-c-2-sync` → `feat/plan-c-3-invite`
**Predecessor:** Plan B complete (tag `plan-b-complete`, 90 tests, `flutter analyze` clean) on branch `feat/plan-b-local-logging`

---

## 1. Goal

Enable two or more devices in a single family to share encrypted baby-care logs through Supabase, without any account or password, while preserving the privacy promise: **Supabase sees only ciphertext and metadata; the family key never leaves the family's devices**.

By the end of Plan C:
1. Mom can generate an invite (QR + 8-char code) and share it via in-person scan or any messenger.
2. A second device can scan the QR or enter the code, derive the family key, and join the family.
3. Every write made on any joined device replicates to every other joined device within ~5 seconds while the apps are foregrounded.
4. Mom can revoke any caregiver, after which the revoked device can neither read new rows nor write to the family.
5. All data on Supabase is AES-GCM ciphertext bound to the row's identity via AAD; a Supabase compromise yields no plaintext.

---

## 2. Locked decisions (from brainstorming 2026-05-14)

| # | Decision |
|---|---|
| Q1 | Plan C is **3 sub-plans**: C-crypto → C-sync → C-invite. Each ships with its own tag. |
| Q2 | **Revocation + key rotation ship in v1.0** (not deferred). BIP-39 recovery phrase deferred to v1.1 opt-in. |
| Q3 | **Foreground-only sync** in v1.0: Supabase Realtime + app-resume + pull-to-refresh. WorkManager / BGTaskScheduler deferred to v1.1. |
| Q4 | **Free tier = max 1 invited caregiver** (= 2 total seats: admin + 1); premium = unlimited. Revised down from 2 per marketing competitive analysis 2026-05-14 — strongest paywall hit (hit freq 6/60d, emotional weight 9 at nanny onboarding). Revoke is unconditionally free. Permission tiers (read-only / admin / co-admin) remain premium. |
| R1 | **Encryption lives in the sync layer**, not in repositories. Plan B repositories work with plaintext; the sync worker encrypts on push and decrypts on pull. SQLCipher continues to encrypt at rest. |
| QR | **QR is the primary share method**; QR encodes the Universal Link (`https://dreambook.app/join/<code>`); manual code entry remains as fallback; deep-link arrival never auto-consumes — user must confirm via JoinConfirmScreen. |
| Q5 | **Admin model**: the device that creates the family is `role='admin'` and is the sole authority to invite, revoke, and change roles. Other caregivers default to `role='editor'`. Only admin can promote/demote (premium-gated). The admin can never self-revoke if they are the sole admin. |
| Q6 | **Remote wipe on revoke**: revoked devices that come online after revocation receive a server-side signal and wipe their local DB + secure storage before showing the "you have been removed" modal. Offline revoked devices retain the local data they previously synced until they come online again — disclosed in privacy policy. |

These decisions are binding. If implementation reveals a blocker, surface to the human before deviating.

---

## 3. Sub-plan structure

### 3.1 C-crypto — branch `feat/plan-c-1-crypto`, tag `plan-c1-crypto-complete`

Scope: crypto primitives, key storage, device identity, schema migration. No network code. Offline-testable end to end.

Deliverables:
- `lib/core/crypto/family_key_service.dart` — generate / store / rotate `K_family` via `flutter_secure_storage` (alias `dreambook_family_key_v1`), iOS accessibility `first_unlock_this_device_only`, Android `EncryptedSharedPreferences`. Load on-demand only; never cached in a `keepAlive` provider.
- `lib/core/crypto/crypto_envelope.dart` — pure-function `seal` / `open` over AES-GCM-256 with random 96-bit nonce. AAD = `${table}|${record_id}|${version}|${family_id}|${key_version}`. Backed by `cryptography_flutter` (native AES-GCM via JNI on Android, CryptoKit on iOS) — not the pure-Dart `cryptography` package.
- `lib/core/crypto/invite_code_service.dart` — CSPRNG 40-bit code → Crockford base32 `XXXX-XXXX`; BLAKE2b code hash; Argon2id KDF (m=64 MiB, t=3, p=1, salt=16 B, output=32 B) producing wrap key; wrap/unwrap `K_family` with AAD = family_id.
- `lib/core/crypto/device_identity_service.dart` — Ed25519 keypair generated on first launch; privkey persists in secure storage (alias `dreambook_device_priv_v1`); pubkey transmitted to the server as the device fingerprint.
- `lib/core/crypto/key_rotation_service.dart` — orchestrates rotation; idempotent resume on crash via local `key_rotation_state` table.
- `lib/core/crypto/secure_wipe.dart` — helper `secureWipe(Uint8List)` (overwrite + nil reference); documented as defense-in-depth, not a guarantee.
- `lib/core/db/migrations/m003_v3.dart` — appended to `Migrations([m001Initial, m002V2, m003V3])` in `lib/core/db/database_provider.dart`. Migration steps:
  - Add `family_id TEXT NOT NULL DEFAULT ''` and `key_version INTEGER NOT NULL DEFAULT 1` to: `baby`, `caregiver`, `pump_session`, `stash_bottle`, `feed`, `diaper`, `sleep`, `vaccination`.
  - Backfill `family_id` for any existing rows with a single auto-generated UUID stored in a new `family_metadata` table.
  - Create `family_metadata(id TEXT PK, current_key_version INTEGER NOT NULL DEFAULT 1, created_at TEXT)`.
  - Create `key_rotation_state(family_id TEXT PK, target_key_version INTEGER, started_at TEXT, last_processed_row TEXT)`.
  - Add `device_pub_key BLOB` column to `caregiver` (nullable; populated at handshake).
- Build config:
  - `pubspec.yaml` gains `cryptography_flutter`, `cryptography`, `convert`, `crypto`. No Supabase deps yet.
  - `android/app/build.gradle` ships `--obfuscate --split-debug-info=build/symbols` via `flutter build` flags documented in `CONTRIBUTING.md` (no code change needed in build.gradle itself — the flag is passed at build invocation time).
  - `android/app/proguard-rules.pro` keeps `sqflite_sqlcipher`, `flutter_secure_storage`, `purchases_flutter` symbols.
  - `tool/check_manifest_security.sh` — static check that no `ContentProvider` / `Service` / `Receiver` is exported and no `sharedUserId` is declared.

Tests (~30):
- Crypto envelope: seal/open round-trip, AAD tamper rejection (5 mutation variants), key swap rejection, version replay rejection, nonce-uniqueness across 10k seals (probabilistic).
- Invite code: entropy chi-square over 10k samples, Crockford ambiguous-char rejection (0/O/1/I/L collapse), BLAKE2b determinism, Argon2id parameter compliance via known-answer vectors.
- Family key service: store / read / rotate round-trip with mock `FlutterSecureStorage`; sentinel self-test detects keystore reset.
- Device identity: Ed25519 sign/verify round-trip; pubkey serialization stable.
- Key rotation resume: simulate crash mid-flight, verify resume picks up at `last_processed_row` and produces same final state as uninterrupted run.
- Migration m003: load v2 DB with sample rows from Plan B fixtures, run m003, assert backfilled `family_id` matches across all rows for a baby, `family_metadata` row exists.

Acceptance gate: `flutter test` passes ≥30 new tests on top of Plan B's 90; `flutter analyze` clean; `tool/check_no_exact_alarms.sh` green; `tool/check_manifest_security.sh` green.

### 3.2 C-sync — branch `feat/plan-c-2-sync`, tag `plan-c2-sync-complete`

Scope: Supabase wiring, sync worker, conflict resolution, key rotation network flow, schema on the server. No caregiver UI yet — Mom can sync with herself across two installs of the same Supabase test project.

Deliverables:
- `pubspec.yaml` gains `supabase_flutter`.
- `lib/core/sync/supabase_client_service.dart` — anonymous auth on first launch, JWT persisted in secure storage (alias `dreambook_supabase_jwt_v1`), refresh on `onAuthStateChange`.
- `lib/core/sync/sync_worker.dart`:
  - Push: query `sync_state WHERE dirty=1`, for each row fetch plaintext from owning table, build AAD, seal, `POST /rest/v1/encrypted_rows`, on 200 update `sync_state` (`dirty=0`, `last_synced_at=now`).
  - Pull-on-resume: query `encrypted_rows WHERE family_id=? AND updated_at > last_pull_at` paginated, decrypt, apply via `ConflictResolver`.
  - Debounce: writes within 500 ms collapse into one push pass.
- `lib/core/sync/realtime_subscriber.dart` — single channel per family subscribing to `encrypted_rows` INSERT/UPDATE; auto-reconnect with exponential backoff; on incoming row, route to `SyncWorker.onIncomingRow`.
- `lib/core/sync/conflict_resolver.dart` — LWW by `(family_id, table, record_id, version)`. Tie-break: higher `updated_at`; if still equal, lexically larger `written_by_device`. Deterministic; pure function over (local row, remote row).
- `lib/core/sync/sync_status_provider.dart` — exposes `lastSyncedAt`, `inFlight`, `lastError` for UI banner.
- `lib/core/sync/key_distribution_service.dart` — when a peer's `key_version` advances past local, fetch the wrapped key for our device from `key_distribution`, X25519-derive shared, unwrap.
- Supabase project schema (`supabase/migrations/0001_init.sql`):

  ```sql
  CREATE TABLE families (
    id              UUID PRIMARY KEY,
    current_key_version INT NOT NULL DEFAULT 1,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
  );

  CREATE TABLE family_devices (
    device_fp           BYTEA PRIMARY KEY,
    family_id           UUID NOT NULL REFERENCES families(id),
    device_pub_key      BYTEA NOT NULL,
    role                TEXT NOT NULL CHECK (role IN ('admin','editor','readonly')),
    joined_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at          TIMESTAMPTZ,
    wipe_requested_at   TIMESTAMPTZ,  -- set on revoke; polled by target device
    wipe_acked_at       TIMESTAMPTZ,  -- set by target after local wipe (audit trail)
    key_version_at_join INT NOT NULL
  );

  CREATE TABLE encrypted_rows (
    id                 UUID PRIMARY KEY,
    family_id          UUID NOT NULL REFERENCES families(id),
    table_name         TEXT NOT NULL,
    record_id          TEXT NOT NULL,
    version            INT NOT NULL,
    key_version        INT NOT NULL,
    ciphertext         BYTEA NOT NULL,
    aad_hash           BYTEA NOT NULL,
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at         TIMESTAMPTZ,
    written_by_device  BYTEA NOT NULL,
    UNIQUE (family_id, table_name, record_id, version)
  );

  CREATE TABLE invites (
    code_hash       TEXT PRIMARY KEY,
    family_id       UUID NOT NULL REFERENCES families(id),
    salt            BYTEA NOT NULL,
    wrapped_key     BYTEA NOT NULL,
    expires_at      TIMESTAMPTZ NOT NULL,
    consumed_at     TIMESTAMPTZ,
    claim_device_fp BYTEA
  );

  CREATE TABLE key_distribution (
    family_id            UUID NOT NULL REFERENCES families(id),
    recipient_device_fp  BYTEA NOT NULL REFERENCES family_devices(device_fp),
    key_version          INT NOT NULL,
    wrapped_key          BYTEA NOT NULL,
    delivered_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (family_id, recipient_device_fp, key_version)
  );
  ```

- RLS policies (`supabase/migrations/0002_rls.sql`):
  - `encrypted_rows` INSERT: requires an active (`revoked_at IS NULL`) row in `family_devices` for `auth.uid()` with role `editor|admin` and `key_version = families.current_key_version` and `written_by_device = auth.uid()::bytea`.
  - `encrypted_rows` UPDATE/DELETE: same plus `family_id` matches the device's family.
  - `encrypted_rows` SELECT: any active device of the same `family_id`.
  - `key_distribution` SELECT: only `recipient_device_fp = auth.uid()::bytea`.
  - `key_distribution` INSERT: only by admin role (mom).
  - `family_devices` SELECT: members of the same family.
  - `family_devices` INSERT/UPDATE/DELETE: only via Edge Functions (`SECURITY DEFINER`).
  - `invites` SELECT/INSERT/UPDATE/DELETE: only via Edge Functions; direct table access denied.
- Edge Functions (`supabase/functions/`):
  - `claim_invite(code, device_fp, device_pub_key)` — atomic claim: BLAKE2b the code server-side, lock the row, check TTL + not consumed + attempt counter ≤ 5 per code_hash, set `consumed_at` + `claim_device_fp`, insert `family_devices`, insert `key_distribution` row for the new device, return `(salt, wrapped_key, family_id, key_version)`. 429 if rate-limited; 410 if expired; 404 if not found.
  - `revoke_caregiver(target_device_fp)` — only callable by admin device of the family; sets `revoked_at`, increments `families.current_key_version`, returns surviving device pubkeys.
  - `cleanup_tombstones` — cron-style scheduled function (Supabase Edge Scheduler if available, else GitHub Actions cron hitting the function URL with a service-role key stored only as Edge Function secret) — `DELETE FROM encrypted_rows WHERE deleted_at < now() - INTERVAL '90 days'`. Daily at 04:00 UTC (off-peak for both TH and USA).
- Network hardening:
  - Android `res/xml/network_security_config.xml` blocks user CAs and sets `cleartextTrafficPermitted="false"` in release builds.
  - iOS `Info.plist`: confirm `NSAllowsArbitraryLoads=false`.
  - Android `res/xml/data_extraction_rules.xml` (API 31+) excludes `flutter_secure_storage` SharedPreferences and the SQLCipher DB file from `cloudBackup` and `deviceTransfer`.
  - iOS: mark DB file and secure storage entries `NSURLIsExcludedFromBackupKey = true`; Keychain items already `kSecAttrSynchronizable = false` via `first_unlock_this_device_only`.
- App-resume + pull-to-refresh wiring in `app_router.dart` and Home (Riverpod listener on `appLifecycleProvider`).

Tests (~25):
- Sync worker push happy path: dirty row → ciphertext POST → on success, `sync_state.dirty=0`.
- Sync worker push retry: network error → backoff → retry on next resume; `sync_state.dirty` stays 1.
- Sync worker push RLS reject: 403 → stop worker, emit `RLSReject` to status provider.
- Pull happy path: receive `encrypted_rows` row → decrypt → upsert via repository → `sync_state.dirty` stays 0 (don't re-push pulled rows).
- Pull tamper rejection: row arrives with mismatched `aad_hash` → discard, log breadcrumb, no upsert.
- Pull decrypt failure: row arrives encrypted with wrong key version → discard with `DecryptFailure`.
- LWW conflict: local v3 + remote v3 with different `written_by_device` → tie-break by `updated_at`, then by `written_by_device`; deterministic.
- LWW tombstone: local v3 alive + remote v4 deleted → local becomes deleted.
- Realtime subscribe lifecycle: connect on auth, reconnect on websocket drop, disconnect on logout.
- Key rotation end-to-end (in-memory 2-device fixture): rotate K_family → revoked device's INSERT returns 403 → surviving device picks up `K_family_v2` via X25519 from `key_distribution` → existing rows re-encrypted under v2 are decryptable; v1 rows are not.
- Mid-rotation crash recovery: kill the worker after 50% of rows re-encrypted → resume on next launch → final state identical to uninterrupted run.

Acceptance gate: `flutter test` adds ≥25 tests; manual smoke: install on Pixel emulator A, log a feed, check Supabase dashboard shows a row with `ciphertext` field as binary (use `psql` or SQL editor to inspect — must be unreadable bytes); install on emulator B, anon-sign in same Supabase project, force-share the same `family_id` (via debug CLI helper), confirm pull decrypts and Feed list shows the row.

### 3.3 C-invite — branch `feat/plan-c-3-invite`, tag `plan-c3-invite-complete`

Scope: end-to-end onboarding UI, QR generation + scanning, deep-link landing, caregiver list, revoke flow, free-tier gating, app hardening that has user-facing surface area.

Deliverables:
- `pubspec.yaml` gains `qr_flutter`, `mobile_scanner`, `permission_handler`, `share_plus`, `freerasp`, `screen_protector` (or platform-channel equivalent).
- `lib/features/share/data/invite_repository.dart` — create invite (calls crypto + POST), list active invites (their TTL), expire invite locally on countdown reach 0.
- `lib/features/share/data/caregiver_repository.dart` — CRUD aligned with Plan B convention.
  - `create()` enforces free-tier gate: `if (!premium && activeCaregivers >= 1) throw CaregiverLimitException(limit: 1)` (= 1 invited; admin + 1 caregiver = 2 total seats free). Also enforces caller is admin: `if (callerRole != 'admin') throw NotAuthorizedException`.
  - `revoke(targetDeviceFp)` is admin-only; calls `revoke_caregiver` Edge Function (which atomically sets `revoked_at`, bumps `current_key_version`, AND inserts a `wipe_requested_at` flag on the target's `family_devices` row), then triggers `KeyRotationService.rotate()`.
  - `changeRole(targetDeviceFp, newRole)` is admin-only and premium-gated (free tier all caregivers are forced `'editor'`).
  - Self-revoke guard: if `callerDeviceFp == targetDeviceFp` AND target is the only admin → throw `SoleAdminGuard`.
- `lib/features/share/presentation/share_invite_screen.dart` — replaces the placeholder. UI: full-bleed QR (encodes Universal Link), 8-char code below in monospace selectable text, countdown timer, three action buttons (Share Link via OS share sheet, Copy Code, Show full-screen QR). `FLAG_SECURE` enabled. App-switcher blur enabled via `screen_protector`. Clipboard auto-clear after 60 s with sensitivity flags (`EXTRA_IS_SENSITIVE` on Android API 33+, `UIPasteboard expirationDate + localOnly` on iOS 14+).
- `lib/features/share/presentation/join_code_screen.dart` — two CTAs: "Scan QR" (primary, opens scanner) and "Enter code manually" (secondary). Scanner uses `mobile_scanner` + camera permission flow with graceful fallback to manual entry on denial. Manual entry: two 4-char fields, auto-uppercase, strip ambiguous chars (0/O/1/I/L collapse). `FLAG_SECURE` enabled.
- `lib/features/share/presentation/join_confirm_screen.dart` — deep-link landing page. Shows family preview (family display name if Mom provided one during invite creation, otherwise generic), invited-by, expiry countdown, two buttons (Yes, Join / Cancel). Never auto-consumes — requires a user gesture.
- `lib/features/share/presentation/caregivers_list_screen.dart` — list active and revoked caregivers with role chips (Admin / Editor / Read-only). Available actions depend on caller role:
  - Admin caller: invite, revoke, change role (premium), promote-to-admin (premium).
  - Non-admin caller: read-only list, no action buttons; revoke/invite buttons hidden with help text "ติดต่อแอดมิน (mom) เพื่อจัดการคนในครอบครัว".
  - Admin self-revoke blocked if sole admin (button disabled with tooltip).
  - Revoke confirmation dialog warns: "Removing this caregiver will rotate the family key and request a wipe of their device. If their device is offline, locally cached data remains on their phone until they come online again."
- `lib/core/router/app_router.dart` adds routes `/share/join` (manual entry) and `/share/join/confirm` (deep-link landing with code query param). Universal Link host registered.
- `lib/features/onboarding/presentation/welcome_screen.dart` adds a second CTA "ฉันมีรหัสครอบครัวอยู่แล้ว / I have a family code" → navigates to `/share/join`. Existing "create new family" path still runs through `_start()`.
- Universal Link / App Link setup:
  - Android: `<intent-filter>` with `android:autoVerify="true"` on `dreambook.app` and `/join/*` path.
  - iOS: associated domains entitlement `applinks:dreambook.app`.
  - `.well-known/assetlinks.json` and `apple-app-site-association` hosted at `https://dreambook.app/.well-known/`. **Manual prep:** the human must register `dreambook.app` (or a chosen subdomain) and host the two files before this sub-plan starts.
- `lib/core/security/freerasp_service.dart` — wraps `freerasp` plugin. On detect (root / jailbreak / Frida / emulator / debugger): show one-time modal, persist user-acknowledged state, transition `syncStatusProvider` to `degraded.localOnly` (Sync worker disabled). Skip the warn in debug builds.
- L10n: every new string in `app_en.arb` and `app_th.arb`. Re-run `flutter gen-l10n`.

Tests (~15):
- Caregiver gating: free + 1 active invited → 2nd `create()` throws `CaregiverLimitException(limit: 1)`. Premium + 1 active → 2nd succeeds. Self (admin) does not count toward the limit.
- Revoke flow: revoke a caregiver → key rotation triggered → caregiver table row's `revoked_at` set, `device_pub_key` retained for audit.
- QR generation round-trip: build `https://dreambook.app/join/MK29-HFX4` → encode → decode → exact match.
- QR scanner: malformed URL → "QR นี้ไม่ใช่รหัส DreamBook" toast; valid URL → navigate to `/share/join/confirm`.
- Manual entry validation: ambiguous chars rejected, 8-char enforced, code format `XXXX-XXXX` accepted with or without dash, padding case-insensitive.
- Deep-link arrival cold-start: process restart with `https://dreambook.app/join/MK29-HFX4` → lands on JoinConfirmScreen, NOT auto-consumed.
- Deep-link arrival warm-start: same, never auto-consumed.
- Clipboard auto-clear: copy code → 60 s passes → clipboard cleared if still contains the code; if user copied something else in the meantime, leave it alone.
- `freerasp` detection in debug build is skipped; in mocked-detect mode triggers degraded state.
- Welcome screen: tapping "I have a code" navigates to `/share/join`, doesn't create a baby.
- Admin model: non-admin caller sees revoke/invite buttons hidden; admin sees them; sole-admin self-revoke blocked with tooltip.
- Remote wipe: simulate `wipe_requested_at` set on self → on next launch, full-screen modal fires; on dismiss, local DB + secure storage + prefs all cleared; app returns to Welcome.
- Co-admin promotion (premium): admin promotes editor → target device receives K_family via key_distribution → can now invite/revoke.

Acceptance gate (end-to-end 2-emulator manual): Pixel A (Mom) creates family + invite → QR shown. Pixel B (Dad) cold-starts, scans QR via `mobile_scanner`, lands on JoinConfirmScreen, taps Yes, joins. Mom logs a feed → Dad's Home shows the feed within 5 s. Mom revokes Dad → Dad attempts to log → RLSReject modal appears.

---

## 4. Architecture

```
┌────────────────────────────────────────────────────────────┐
│ PRESENTATION (features/share/presentation/*)               │
│   WelcomeScreen ─┬─ "I have a code"      → JoinCodeScreen  │
│                  └─ "Start new family"   → existing flow   │
│   ShareInviteScreen · JoinCodeScreen · JoinConfirmScreen   │
│   CaregiversListScreen                                     │
└──────────────────────────┬─────────────────────────────────┘
                           │ Riverpod providers
┌──────────────────────────▼─────────────────────────────────┐
│ APPLICATION                                                │
│   syncWorkerProvider · keyRotationServiceProvider          │
│   inviteSessionProvider · caregiverListProvider            │
│   syncStatusProvider · freeraspStatusProvider              │
└──────┬────────────────────────────────────┬────────────────┘
       │                                    │
┌──────▼────────────────┐   ┌────────────────▼───────────────┐
│ DATA (repositories)    │  │ SYNC (lib/core/sync/*)         │
│   CaregiverRepository★ │  │   SupabaseClientService        │
│   InviteRepository★    │  │   SyncWorker                   │
│   Plan B repos         │  │   RealtimeSubscriber           │
│   (unchanged — R1 win) │  │   ConflictResolver             │
│                        │  │   KeyDistributionService       │
└──────┬─────────────────┘  └────────┬───────────────────────┘
       │ plaintext rows + sync_state │ ciphertext rows
       │                              │
┌──────▼──────────────────────────────▼──────────────────────┐
│ CRYPTO (lib/core/crypto/*) — pure Dart, no Flutter deps    │
│   FamilyKeyService · CryptoEnvelope · InviteCodeService    │
│   DeviceIdentityService · KeyRotationService · secureWipe  │
└──────┬─────────────────────────────────────────────────────┘
       │ secrets
┌──────▼─────────────────────────────────────────────────────┐
│ STORAGE                                                    │
│   flutter_secure_storage  → K_family, device_privkey, JWT  │
│   sqflite_sqlcipher (Plan B)  → plaintext + sync_state     │
│   Supabase (remote)  → encrypted_rows · invites · families │
└────────────────────────────────────────────────────────────┘
```

### Layer rules

1. Crypto layer is pure Dart — no Flutter framework, no Supabase, no `dart:io` beyond `Uint8List`.
2. Sync layer is the only consumer of `supabase_flutter`. Repositories must not import it.
3. Repositories return plaintext to the UI. UI sees sync state only via `syncStatusProvider`.
4. AAD must bind `family_id` and `key_version` on every seal/open.
5. Every repository write that produces a `sync_state.dirty=1` row must do so inside the same DB transaction as the data write.
6. Crypto keys are loaded on-demand and dropped after use. No `keepAlive` provider holds key material.

---

## 5. Data flows

### 5.1 Write replication

```
Mom phone:
  FeedRepository.insert(...)                  [Plan B — UNCHANGED]
    ├─ INSERT INTO feed (...)
    └─ INSERT/UPDATE sync_state SET dirty=1
                                       
  SyncWorker (debounced 500 ms / on resume):
    SELECT * FROM sync_state WHERE dirty=1
    FOR each dirty row:
      plaintext = SELECT * FROM <table> WHERE id = record_id
      aad = "${table}|${record_id}|${version}|${family_id}|${key_version}"
      nonce = CSPRNG(12)
      ct = AES_GCM_encrypt(K_family, nonce, json(plaintext), aad)
      aad_hash = BLAKE2b(aad)
      → POST /rest/v1/encrypted_rows
         { family_id, table, record_id, version, key_version,
           ciphertext = nonce || ct, aad_hash, deleted_at, written_by_device }
      on 200:
        UPDATE sync_state SET dirty=0, last_synced_at=now() WHERE ...

Supabase:
  RLS check on INSERT (see C-sync RLS policies)
  Realtime broadcasts INSERT to family channel

Peer phone:
  RealtimeSubscriber → SyncWorker.onIncomingRow(row)
    expected_aad = "${row.table}|${row.record_id}|${row.version}|${row.family_id}|${row.key_version}"
    if BLAKE2b(expected_aad) != row.aad_hash  → REJECT (tampered)
    nonce, ct = row.ciphertext[0:12], row.ciphertext[12:]
    plaintext = AES_GCM_decrypt(K_family, nonce, ct, expected_aad)
    ConflictResolver.upsert(table, record_id, plaintext, row.version)
       LWW + tie-break (updated_at, written_by_device)
    sync_state row is NOT marked dirty (don't re-push pulled data)
  UI rebuilds via Riverpod stream from repo
```

Time budget on mid-tier Android: seal ~5 ms, network ~150 ms, Realtime fan-out + open ~200 ms → ~5 s worst case.

### 5.2 Invite handshake

```
Mom (ShareInviteScreen):
  code = crockford32(CSPRNG(40 bits))          → "MK29-HFX4"
  salt = CSPRNG(16)
  K_kdf = Argon2id(password=code, salt=salt, m=64MiB, t=3, p=1, len=32)
  wrapped = AES_GCM_encrypt(K_kdf, nonce=CSPRNG(12), K_family, aad=family_id)
  code_hash = BLAKE2b(code)
  POST /rest/v1/rpc/create_invite  { code_hash, family_id, salt,
                                     wrapped_key=nonce||wrapped,
                                     expires_at = now()+1h }
  Display QR (encodes "https://dreambook.app/join/MK29-HFX4")
  Display code "MK29-HFX4" + 60 min countdown
  FLAG_SECURE on; app-switcher blur on

Dad (deep-link via QR scan or messenger tap):
  OS routes "https://dreambook.app/join/MK29-HFX4"
  → AndroidManifest/iOS associated domains  → app opens → JoinConfirmScreen
  User taps "Yes, join family"
  device_priv, device_pub = Ed25519 keypair (from DeviceIdentityService)
  POST /functions/v1/claim_invite { code, device_fp = anon_uid, device_pub_key }
    Edge Function (server-side):
      code_hash = BLAKE2b(code)
      SELECT * FROM invites WHERE code_hash = code_hash
              AND expires_at > now() AND consumed_at IS NULL
              FOR UPDATE
      attempts = increment attempt counter for code_hash
      if attempts > 5: mark dead, return 410
      if no row: return 404
      UPDATE invites SET consumed_at = now(), claim_device_fp = device_fp
      INSERT family_devices (device_fp, family_id, device_pub_key,
                             role='editor', joined_at = now(),
                             key_version_at_join = current_key_version)
      INSERT key_distribution (family_id, recipient_device_fp,
                               key_version, wrapped_key = invites.wrapped_key)
      return { salt, wrapped_key, family_id, key_version }
  K_kdf = Argon2id(code, salt, ...)
  K_family = AES_GCM_decrypt(K_kdf, wrapped_key, aad = family_id)
  FamilyKeyService.store(K_family, key_version, family_id)
  Trigger initial pull of encrypted_rows for family_id
  SharedPreferences set onboarding.done = true
  Navigate Home
```

Rate-limit: max 5 failed attempts per `code_hash` (then mark dead). Max 20 claim attempts per anon user per hour (semantic; enforced in Edge Function). Cloudflare in front provides per-IP volumetric protection (DDoS shield).

### 5.3 Key rotation on revoke

```
Mom (CaregiversListScreen → Revoke caregiver C):
  K_family_v2 = CSPRNG(32)
  new_version = current_key_version + 1
  
  // 1. Mark revocation on server first (atomic)
  POST /functions/v1/revoke_caregiver { target_device_fp, new_key_version }
    Edge Function:
      UPDATE family_devices SET revoked_at = now(),
                              wipe_requested_at = now()
        WHERE device_fp = target
      UPDATE families SET current_key_version = new_version
      return list of surviving (device_fp, device_pub_key)
  
  // 2. Persist local rotation intent
  INSERT INTO key_rotation_state (family_id, target_key_version=new_version, started_at=now())
  
  // 3. Re-encrypt active rows under K_family_v2 (skip tombstones)
  FOR each row in encrypted_rows WHERE family_id = ? AND deleted_at IS NULL:
    plaintext = decrypt with K_family_v1
    ciphertext_v2 = encrypt with K_family_v2 (AAD includes new_version)
    PATCH encrypted_rows SET ciphertext=ciphertext_v2, key_version=new_version
    UPDATE key_rotation_state SET last_processed_row = row.id
  
  // 4. Distribute K_family_v2 to surviving devices via X25519
  FOR each surviving (recipient_device_fp, recipient_pub_key):
    shared = X25519(my_priv, recipient_pub_key)
    wrapped = AES_GCM_encrypt(shared, K_family_v2)
    INSERT INTO key_distribution (family_id, recipient_device_fp,
                                  key_version=new_version, wrapped_key=wrapped)
  
  // 5. Local: switch active key, clear rotation state
  FamilyKeyService.store(K_family_v2, new_version)
  DELETE FROM key_rotation_state WHERE family_id = ?

Surviving caregiver phones (poll key_distribution on app resume / receive Realtime notification):
  IF my recipient row in key_distribution has key_version > local_version:
    shared = X25519(my_priv, family_admin_pub)
    K_family_vN = AES_GCM_decrypt(shared, wrapped_key)
    FamilyKeyService.store(K_family_vN, new_version)
    Trigger re-pull of encrypted_rows

Revoked phone (still has K_family_v1):
  All future inserts REJECTED by RLS (key_version mismatch on row vs families.current_key_version)
  All future pulls return rows under K_family_v2 → decrypt fails silently
  Local cached data remains plaintext on the revoked device until step 5.4 fires
```

Atomicity: step 1 (server-side revoke + version bump) completes before step 3 (client re-encryption). If the client crashes after step 1, `key_rotation_state` persists; on next launch, `KeyRotationService.resume()` reads the state and continues from `last_processed_row`. The re-encrypt loop is idempotent: each row is checked against `key_version` before re-encrypting.

### 5.4 Remote wipe of revoked device

When an admin revokes a caregiver, the `revoke_caregiver` Edge Function also sets `family_devices.wipe_requested_at = now()` on the target row. Every client polls its own `family_devices` row on app launch and on every sync cycle (cheap — single row).

```
Revoked caregiver phone, on next launch (or next foreground after revocation, whichever first while online):
  SELECT wipe_requested_at FROM family_devices WHERE device_fp = self_device_fp
  IF wipe_requested_at IS NOT NULL:
    1. Show full-screen modal: "You have been removed from this family."
    2. On user dismiss (only option, no cancel):
       - DELETE all rows from baby, caregiver, feed, pump_session, stash_bottle,
         diaper, sleep, vaccination, family_metadata, sync_state
       - FlutterSecureStorage.deleteAll() — removes K_family, device_priv, JWT
       - SharedPreferences.clear()
       - Optionally: POST /functions/v1/ack_wipe { device_fp }  (audit trail; non-blocking)
    3. App restart → Welcome screen, no trace of prior family
```

Honest disclosure (privacy policy):
> "When an admin removes you from a family, your device will erase its local copy of the family's data the next time it connects to the internet. If your device stays offline, the data on your phone remains until you connect again. We cannot reach offline devices to perform the erase."

This is the best a client-side system can offer without push notifications carrying privileged commands. The combination of (a) key rotation immediately invalidates writes/reads to the server, and (b) remote-wipe-on-next-connect erases local state on the vast majority of revoked devices that come online within hours.

### 5.5 Admin model and role transitions

| Role | Can log entries | Can view entries | Can invite | Can revoke | Can change roles | Can promote to admin |
|---|---|---|---|---|---|---|
| `admin` (free + premium) | ✅ | ✅ | ✅ | ✅ | premium | premium |
| `editor` (free default) | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| `readonly` (premium only) | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |

In v1.0 free tier, every caregiver other than the family creator is forced to `editor`. Premium unlocks role tiers AND co-admin (promote one editor to admin — a partial recovery story for "what if mom loses her phone").

Sole-admin guard: if a family has exactly one admin, that admin cannot be revoked, demoted, or self-revoked. UI shows the action disabled with tooltip "Add a co-admin first (premium)."

Co-admin (premium, v1.0): when an editor is promoted to admin, they receive `K_family` via X25519 fan-out (same mechanism as rotation). The promoted device can then invite, revoke, and rotate independently. If the original admin loses their phone, the co-admin can revoke them and continue. This is the v1.0 recovery story — BIP-39 recovery phrase remains deferred to v1.1.

---

## 6. Mobile hardening (from auditor #2)

### 6.1 Ship in Plan C

| # | Measure | Sub-plan |
|---|---|---|
| 1 | App Links (Android) / Universal Links (iOS) for invite deep link + manual confirm landing | C-invite |
| 2 | `--obfuscate --split-debug-info`, ProGuard keep rules, `cryptography_flutter` native AES-GCM | C-crypto + build |
| 3 | `freerasp` soft-warn on root/jailbreak (degrade to local-only, never hard-block) | C-invite |
| 4 | `FLAG_SECURE` on ShareInviteScreen + JoinCodeScreen only (NOT CaregiversListScreen) | C-invite |
| 5 | Clipboard auto-clear after 60 s + `EXTRA_IS_SENSITIVE` (Android 13+) + `expirationDate` + `localOnly` (iOS 14+) | C-invite |
| 6 | App-switcher blur via `screen_protector` (Android `setRecentsScreenshotEnabled(false)` API 33+; iOS willResignActive overlay) | C-invite |
| 7 | Android `network_security_config.xml` blocks user CAs, `cleartextTrafficPermitted="false"` | C-sync |
| 8 | Android `data_extraction_rules.xml` (API 31+) excludes secure storage + DB from cloud backup and device transfer | C-sync |
| 9 | iOS `NSURLIsExcludedFromBackupKey = true` on DB + secure storage entries | C-sync |
| 10 | iOS Keychain `accessibility = first_unlock_this_device_only` (NOT `first_unlock`) — overrides initial Plan A choice | C-crypto |
| 11 | `tool/check_manifest_security.sh` static check: no exported components, no `sharedUserId` | C-crypto |
| 12 | K_family loaded on-demand only, never cached in `keepAlive` provider | C-crypto |

### 6.2 Explicitly skipped

| Measure | Reason |
|---|---|
| TLS certificate pinning | Supabase cert rotation = global outage risk; E2E AES-GCM already neutralizes MITM (attacker sees ciphertext) |
| String encryption / DexGuard / iXGuard | Indie budget, low ROI, breaks Flutter hot reload |
| Hard-block on root | False positive ~3–8% on enthusiast Android (LineageOS / Magisk Zygisk-hidden); soft-warn covers the threat without burning reviews |
| Anti-Frida deep hooks / anti-ptrace | `freerasp` default detection sufficient for this threat model; deep hooks are dev-weeks for a threat actor that does not exist for a baby tracker |
| In-app malicious update defense | Cannot defend against own signed update; mitigate at the source (Play Console 2FA + Play App Signing, App Store Connect 2FA) |
| `Uint8List` zero-fill as a guarantee | Dart VM may have GC-copied buffers; ship `secureWipe()` helper as defense-in-depth but document as theater |

### 6.3 Deferred to Plan F (polish)

- Play Integrity API (Android) / App Attest (iOS) — increases tamper-resistance, not launch-blocking.
- Screen-recording detection overlay beyond what `FLAG_SECURE` already covers.
- Anti-debug runtime checks beyond `freerasp` defaults.

---

## 7. Error handling

| Error class | Trigger | Behavior | UI surface |
|---|---|---|---|
| `NetworkError` | timeout / offline | exponential backoff 500 ms → 30 s cap, retry on resume, row stays `dirty=1` | silent banner via `syncStatusProvider` |
| `AuthError` | Supabase 401 / JWT invalid | re-auth anon, retry once; if 2 consecutive failures → "Reconnect" banner | banner |
| `RLSReject` | INSERT 403 (revoked or `key_version` mismatch) | stop SyncWorker; transition to `revokedOrStale` state | hard modal "Removed from family — restart or enter new code", with Wipe & Restart button |
| `DecryptFailure` | local `open()` mismatch | discard row, log breadcrumb (no plaintext/ciphertext content), count occurrences | if >3 in 24 h → "Data integrity issue" banner |
| `EnvelopeTamper` | `aad_hash` mismatch on incoming row | reject row, log breadcrumb, count occurrences | same as DecryptFailure |
| `InviteExpired` / `InviteDead` | claim returns 410 | clear form, message "Code expired or used — ask Mom for a new one" | inline error |
| `InviteRateLimited` | claim returns 429 | local cooldown 60 s, message "Try again in 60 seconds" | inline error + disabled submit |
| `CaregiverLimitException` | repo throws on free + 1 active invited (= 2 total seats reached) | route to placeholder paywall sheet | bottom sheet |
| `KeyRotationCrash` | app killed mid-rotation | resumable from `key_rotation_state`; idempotent re-encrypt | silent background; banner only after 3 resume failures |
| `KeystoreReset` | sentinel self-test fails on launch | force re-handshake flow, wipe local DB | full-screen onboarding |
| `RoOtDetected` (sic, `freerasp`) | root / jailbreak / Frida / emulator / debugger | one-time soft modal, persist user choice, transition `syncStatusProvider` to `degraded.localOnly`, disable sync worker | modal |
| `WipeRequested` | `family_devices.wipe_requested_at IS NOT NULL` for self | full-screen modal "You have been removed from this family" → on dismiss wipe all local state (DB + secure storage + prefs) → Welcome | full-screen modal, no cancel |
| `NotAuthorizedException` | non-admin attempts admin-only action (invite, revoke, role change) | throw + log; UI hides the button in the first place, so this is defense-in-depth | none (UI prevents) |
| `SoleAdminGuard` | admin tries to self-revoke or demote when sole admin | block at UI + repo layer | tooltip "Add a co-admin first (premium)" |

**Logging policy:**
- Crypto failures log only `{class, table_name, count, timestamp}` — never ciphertext, plaintext, AAD content, code, or invitee identifiers.
- No PII in logs ever.
- Local breadcrumb buffer (last 50 events) — user can copy via Settings → Support.
- Crashlytics is opt-in only and is not added in Plan C (added in Plan F).

---

## 8. Testing strategy

Targets:
- C-crypto: ≥30 new tests
- C-sync: ≥25 new tests (incl. fake-server integration)
- C-invite: ≥15 new tests + manual 2-emulator E2E scripted via ADB

Conventions:
- All repository tests follow Plan B convention (in-memory sqflite_ffi + `ProviderContainer` with `appDatabaseProvider` override) per `test/features/feed/feed_repository_test.dart`.
- Sync worker tests use a custom in-memory HTTP fake implementing the subset of Supabase REST + Realtime we depend on. The fake lives at `test/_fakes/fake_supabase.dart`.
- Crypto tests use known-answer vectors where available (AES-GCM via NIST test vectors; Argon2id via reference implementation outputs).
- Verification commands:

  ```bash
  flutter analyze                       # clean
  flutter test                          # all pass; target ≥160 after Plan C
  flutter test test/core/crypto/        # C-crypto subset
  flutter test test/core/sync/          # C-sync subset
  flutter test test/features/share/     # C-invite subset
  tool/check_no_exact_alarms.sh         # OK
  tool/check_manifest_security.sh       # OK
  ```

Manual end-to-end (documented as a checklist in `docs/runbooks/plan-c-e2e.md`):
1. Two Pixel emulators (or one + a real device). Same Supabase test project.
2. Device A creates family + invite. QR appears.
3. Device B cold-starts, scans QR, lands on JoinConfirmScreen (verify not auto-consumed). Taps Yes.
4. Device A logs a feed. Device B's Home shows the feed within 5 s.
5. Device A revokes Device B. Device B attempts a feed log → RLSReject modal.
6. Device A re-invites Device B (new code). Device B re-joins. Old data accessible.
7. Force-kill Device A during step 5's key rotation. Re-launch → rotation resumes and completes.
8. ADB pull the SQLCipher DB file from Device A. Open with sqlite3 → garbled bytes only.

---

## 9. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Argon2id 64 MiB too slow on Android API 23 baseline | Medium | UX 3–5 s wait during onboarding | "Connecting securely…" loading screen; benchmark on Pixel 5 baseline; if >2 s on API 23 → drop to m=32 MiB (auditor approved as hardware fallback) |
| Supabase Edge Function cold-start ~1 s first claim | Medium | First caregiver waits longer | Send warming ping when JoinCodeScreen opens (debounced) |
| `cryptography` Dart Argon2id requires FFI | Medium | Build complexity | Use `cryptography_flutter` (native plugin); fallback `argon2` package |
| Two devices race on identical version | Low (LWW) | Last-second write loss | Tie-break by `updated_at`, then `written_by_device` — deterministic |
| Reinstall produces new anon_uid → device evicted | Low | Caregiver must re-enter code | This is intended; re-handshake flow is the recovery path in v1.0 |
| Mom revokes herself (last admin) | Low | Family lockout | UI blocks `role = admin` self-revoke; the last admin cannot be removed |
| Realtime websocket drops on flaky wifi | High (3 a.m. parents) | Sync delay | Auto-reconnect with backoff; pull-on-resume safety net |
| `dreambook.app` domain registration / DNS / hosting downtime | Low | Universal Links degrade to custom scheme (still functional) | Use a reputable registrar; document fallback in C-invite plan |
| `freerasp` false positives on legitimate customized Android | Medium (3–8% in TH) | Users see soft-warn modal once | Soft-warn only, persist acknowledgment, never hard-block |

---

## 10. Out of scope (v1.0; deferred)

| Item | When |
|---|---|
| BIP-39 12-word recovery phrase (opt-in, premium) | v1.1 |
| WorkManager (Android) / BGTaskScheduler (iOS) background sync | v1.1 |
| Per-row ephemeral keys (selective re-wrap on revoke for forward secrecy) | v1.2 |
| Play Integrity API / App Attest | Plan F |
| Photo per entry, encrypted relay for shared photos | v1.1 |
| AI insights (data-driven; need volume first) | v1.1 |
| DreamBaby bridge (deep) | Plan F |
| Crashlytics (opt-in) | Plan F |

---

## 11. Manual prep checklist (must complete before C-invite starts)

1. Register or designate a domain for Universal Links — recommended `dreambook.app` or `niyoko.studio/dreambook`. The chosen host must be `https://` with a valid TLS cert.
2. Create the Supabase project in region `ap-southeast-1`. Note the project URL and `anon` key.
3. Add `.env.example` to the repo with `SUPABASE_URL=` and `SUPABASE_ANON_KEY=` placeholders; the human pastes real values into `.env` (gitignored).
4. Host `.well-known/assetlinks.json` (Android App Links fingerprint) and `apple-app-site-association` (iOS Universal Links) on the chosen domain. Both files generated from final release-signing fingerprints.
5. Confirm Play Console 2FA + Play App Signing are enabled.

---

## 12. Open questions (surface to writing-plans)

1. Family display name during invite — should mom optionally label the family ("Mali's family") before generating the invite? Affects JoinConfirmScreen preview text. Lean: yes, optional; default to baby's name if a baby exists.
2. QR fullscreen mode — should the full-screen QR view turn the screen brightness to max (for far-distance scanning) and disable auto-lock? Lean: yes, both, while the full-screen view is open.
3. Edge Function deployment automation — is the human OK running `supabase functions deploy` manually, or do we need a CI step? Lean: manual for v1.0; CI in Plan F.
4. Cron for `cleanup_tombstones` — Supabase Edge Scheduler if available in their plan tier, else GitHub Actions cron. Confirm with human at C-sync start.

---

## 13. Marketing positioning + pricing strategy

This section captures the marketing tier structure that informs Plan C scope (specifically the free-caregiver limit of 1 invited) and locks the framework for Plan D paywall implementation. Source: senior marketing competitive analysis 2026-05-14 comparing Huckleberry, Glow Baby, Baby Connect, Baby Tracker (Nighp), BabyDaybook, Sprout Baby, Hatch Baby, Ovia Parenting.

### 13.1 Free tier (final after marketing adjustment)

| Feature | Free |
|---|---|
| Log Feed / Pump / Diaper / Sleep / Vaccination | unlimited |
| Vaccination schedule | CDC / WHO standard only (custom vaccines = premium) |
| Freezer Stash | **5 bottles max**; no expiry alerts (premium) |
| History viewable | **last 7 days**; 30d / 90d shown blurred with one-tap upgrade prompt |
| Babies | 1 |
| Caregivers invited | 1 (= 2 total seats: admin + 1 invited) |
| Caregiver role available to invite | Editor only |
| Revoke caregiver | YES (safety feature, free forever) |
| Remote-wipe of revoked device | YES |
| E2E encryption | YES |
| Basic Daily Summary + Today timeline + FeedSparkline | YES |
| CSV export | 7-day window only (PDF Visit Summary remains premium) |
| No ads | YES |

### 13.2 Premium tier (final)

| Feature | Premium |
|---|---|
| Babies | unlimited |
| Caregivers invited | unlimited |
| Caregiver roles | Editor + Readonly + Co-admin |
| Change caregiver role / promote co-admin | YES |
| Custom feeding types + tags | YES |
| Custom vaccination entries (outside CDC / WHO schedule) | YES |
| Freezer Stash | unlimited + **expiry alerts** |
| History | lifetime |
| CSV export | full lifetime range |
| **Visit Summary PDF** (printable for doctor visit) | YES |
| Weekly / Monthly Insights (charts + trends) | YES |
| AI pattern insights | YES (v1.1) |

### 13.3 The 6 paywall hits (final, ranked by expected conversion)

| # | Trigger | Hit freq / 60 days | Emotional weight | Notes |
|---|---|---|---|---|
| 1 | "View history beyond 7 days" | 9 | 7 | #1 conversion driver after free history cut to 7d. Blurred 30/90d preview is the lever. |
| 2 | "Add 2nd caregiver (3rd seat total)" | 6 | 9 | Hits at nanny onboarding moment — high emotion. |
| 3 | "Freezer expiry alert" (NEW) | 8 | 10 | "Your milk is about to spoil." Pumper segment = highest LTV. |
| 4 | "Export Visit Summary PDF" | 7 | 10 | Pre-trigger preview at first vaccination log (week 1-2 of install) so user sees what they'd hand the pediatrician at the 2-month visit. |
| 5 | "Add 2nd baby" | 2 | 8 | Small TAM (twin/sibling parents) but high conversion when needed. |
| 6 | "View weekly / monthly insights" | 8 | 5 | Nice-to-have, de-emphasize. |

### 13.4 Pricing strategy — decided at Plan D start, not Plan C

Plan C ships sync + crypto + invite plumbing only. Pricing UI and paywall implementation lands in Plan D (RevenueCat). At Plan D start, decide between two paths based on DreamBaby's launch state at that moment:

**Path 1 — DreamBaby launched and selling Lifetime well (≥100 standalone Lifetime / month sustained for 2 consecutive months):**
- Pull DreamBook standalone Lifetime entirely.
- Sell Lifetime only via "Niyoko Baby Bundle" $44.99 (= DreamBook + DreamBaby lifetime).
- Monthly $2.99, Yearly $24.99 (raised from $19.99), Bundle $44.99.
- ARPU on Lifetime SKU: +50% vs standalone.
- Thailand: Monthly 99฿, Yearly 749฿, Bundle 1,299฿.
- DreamBaby keeps its own standalone Lifetime $29.99 — it is the entry product; DreamBook is the upgrade.

**Path 2 — DreamBaby not yet launched, demand uncertain, or Lifetime soft:**
- Keep DreamBook standalone Lifetime $29.99 alongside Bundle $44.99 as optional upsell.
- Monthly $2.99, Yearly $24.99, Lifetime $29.99, Bundle $44.99.
- Safer; lower ARPU but no launch dependency.
- Path can switch to Path 1 in a later release after DreamBaby launch matures.

**Locked regardless of path:**
- Yearly raised from $19.99 to **$24.99** (TH: 749฿). $19.99 signaled "discount/lesser app"; $24.99 sits in BabyDaybook tier without crossing the $29.99 psychological barrier.
- 7-day free trial on subscriptions.
- No ads, ever.
- No standalone IAP for individual features (Visit PDF, expiry alerts, etc.) — these unlock as a bundle under any premium SKU.

### 13.5 Marketing wedges (App Store listing bullets — lean into)

Drawn from features that are EITHER unique vs competitors OR strong differentiators kept free intentionally:

1. **"No account. No email. No password."** No competitor in this space offers this. Glow / Huckleberry / Ovia all require account creation. Store listing screenshot #1.
2. **"Your data is encrypted before it leaves your phone — even we can't read it."** E2E is the hardest technical moat. Ovia was publicly flagged by Mozilla for the opposite.
3. **"Share with grandma without sharing your password."** Huckleberry's official answer to caregiver share is "share your Apple ID login." The no-account-share flow is our viral hook for multi-caregiver households.
4. **"Revoke any caregiver in one tap — and wipe their device copy."** Safety feature, free forever. Marketing copy practically writes itself for the divorce / custody / fired-nanny edge cases competitors silently ignore.
5. **Unlimited core logging** (feed / pump / diaper / sleep / vaccinations). Never cap the core verb. The history wall does the gating work — capping daily logs would feel punitive (1-star review pattern).
6. **No ads, ever.** Brand promise; baby app at 3 a.m. + ad = uninstall + 1-star review. Glow / Ovia eat 1-stars for this; we will not.

### 13.6 Daily Summary as shareable hero (Plan B verification + Plan D / F enhancements)

Plan B shipped DailySummary model + provider + FeedSparkline + DailySummaryScreen + Home nav. Plan C does not modify it. Future enhancements positioned as marketing-acquisition channel:

- **Plan D — "Share today" button**:
  - Free: text share ("Mali · 8 wks · today: 🍼 7 × 410 ml · 😴 14 h · 💩 5").
  - Premium: pretty image card (1080x1080) with mom's chosen theme + DreamBook watermark — gallery save + chat share. Watermark creates organic acquisition loop in LINE / WhatsApp / Instagram.
- **Plan F — Home screen widget** (Android + iOS): "Last feed: 2 h ago · Last sleep: 30 min ago." Free or premium TBD at Plan F start.
- **Plan F — iOS Lockscreen Live Activity** (iOS 16+): "Feeding now · 8 min" while a feed is being timed.

### 13.7 Verification at Plan D start

Before Plan D begins, run a 60-day post-launch check on DreamBaby and verify:
1. DreamBaby is in Play Store with active downloads.
2. Standalone Lifetime SKU has sustained ≥100 sales / month for 2 consecutive months.
3. No major Play Store policy violations or 1-star review cluster.

If all three: proceed with Path 1. Otherwise: Path 2. Decision documented in the Plan D plan file.

---

## 14. References

- Parent spec: `docs/superpowers/specs/2026-05-13-dreambook-design.md`
- Plan A foundation: `docs/superpowers/plans/2026-05-13-foundation.md`
- Plan B sketch: `docs/superpowers/plans/2026-05-13-plan-b-sketch.md`
- Project CLAUDE.md: `/Users/nipitphand/Projects/DreamBook/CLAUDE.md`
- Auditor #1 memo (crypto math): captured in session transcript 2026-05-14
- Auditor #2 memo (mobile hardening): captured in session transcript 2026-05-14
- Sibling app rules: `/Users/nipitphand/Projects/CLAUDE.md`, `/Users/nipitphand/.claude/.../memory/feedback_dreambaby_notifications.md`

---
