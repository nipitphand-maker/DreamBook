# DreamBook — Project Context

## Platform
- Cross-platform Flutter — runs on Android + iOS from one codebase
- **Android first** (Plan A through F all verify on Android emulator); iOS launch ~1-2 months later
- **Android minSdkVersion 23** (diverges from DreamBaby's 21 — required by `purchases_flutter ^10` + `flutter_secure_storage ^10`)
- iOS deployment target 13.0+

## Stack
- Flutter 3.41+, Dart 3.10+
- **Riverpod 3.x with hand-rolled providers** (Plan A — codegen deferred to Plan B due to analyzer-range conflict between `riverpod_generator ^3` and `json_serializable ^6.13`)
- go_router ^17, sqflite_sqlcipher ^3.4, flutter_secure_storage ^10, flutter_localizations + intl, purchases_flutter ^10 (RevenueCat — Plan D+), supabase_flutter (Plan C+), cryptography (Plan C+), pdf+printing (Plan E)
- Notifications: `flutter_local_notifications` ^21 — **inexact only**, never `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM`. Enforced by `tool/check_no_exact_alarms.sh` grep guard.

## Riverpod 3 deltas (gotcha tracker)
- `AsyncValue.valueOrNull` was REMOVED in Riverpod 3 — use `.value` instead (already nullable).
- `StateProvider` / `StateNotifierProvider` moved to `package:flutter_riverpod/legacy.dart` — greenfield code never imports `legacy.dart`.

## Companion app
- DreamBaby is the sibling app at `/Users/nipitphand/Projects/DreamBaby/`
- Many code patterns reused (SecureKeyService, NotificationService inexact rule, l10n_ext.dart)
- Plan F adds the cross-app bridge (deep-link + shared Baby Profile via Android FileProvider / iOS App Group)

## Target market & content
- Primary: USA (English). Secondary: Thailand (Thai). Expansion post-v1.1: ES, PT-BR, JA, KO, DE
- Target user: 0–24 month babies. Pumping moms + multi-caregiver households.

## Features (v1.0 MVP scope per spec D1–D15)
- Feed (breast L/R timer + bottle oz/ml), Pump session (L/R oz), Freezer Stash (visual + expiry alerts), Diaper, Sleep
- **Caregiver share** = differentiator (8-char Crockford base32 `XXXX-XXXX` invite code, 1-hour TTL, E2E AES-GCM in Plan C)
- Daily Summary, Vaccination log, Visit Summary PDF (premium, default 7-day range)
- Multi-baby (premium), RevenueCat paywall (Monthly $2.99 / Yearly $19.99 / Lifetime $29.99 / 7-day trial)

## Privacy & Security
- **No login, no account, no email** — invite code + device ID only
- All local data encrypted at rest via `sqflite_sqlcipher`; DB key in Keychain / EncryptedSharedPreferences
- All synced data encrypted client-side (AES-GCM); Supabase sees only ciphertext + row metadata
- No analytics SDK. Crashlytics opt-in only.
- App data backup disabled (`android:allowBackup="false"`) — would break decryption on restore
- COPPA / GDPR-K / PDPA exposure: age cap 0–24 mo, kids-data lawyer reviews PP/ToS before public launch

## Key architecture decisions
- **Migration runner: append-only `List<MigrationStep>`** in `lib/core/db/migrations/migrations.dart` (greenfield — DreamBaby has no shared runner)
- **Soft-delete pattern**: every syncable row has `deleted_at TEXT` + `version INTEGER`; `sync_state` ledger tracks dirty rows
- **Thai fonts BUNDLED** in `assets/fonts/IBMPlexSansThai-*.ttf` (offline-first for 3 AM parents on flaky wifi)
- **Theme `ColorScheme` explicit, not `fromSeed`** — preserves curated palette across light/dark/nightTint
- **Color tokens**: brand (lavender/peach/sage/honey) FAIL AA on cream (2.03:1 lavender) — they are decorative fills only. Text/icons MUST use `AppColors.ink*` or `AppColors.{name}700` derivatives.
- **Sync (Plan C)**: Supabase region `ap-southeast-1` (Singapore); last-write-wins per `(record_id, version)`
- **Notifications**: inexact only. CI grep guard in `tool/check_no_exact_alarms.sh`.
- **RLS device identity discipline** — two device identities exist and are NEVER interchangeable:
  1. `auth.uid()` — 16-byte Supabase anonymous user UUID (the "caller").
  2. `family_devices.device_fp` — first 16 bytes of `SHA-256(device_pub_key)` (the "device record").
  They are unrelated byte strings. `uuid_send(auth.uid())`, `uuid_bytes(...)`, `decode(auth.uid()::text, 'hex')`, etc. NEVER equal a real `device_fp`. Comparing them in an RLS `USING` / `WITH CHECK` silently denies every row (no error, just empty results → mysterious 403s and `NULL` subqueries that break downstream policies).
  - The canonical "who is the caller" join: `family_devices.auth_user_id = auth.uid()`.
  - The canonical "what families does the caller belong to" helper: `public.current_user_family_ids()` (SECURITY DEFINER, defined in `0011_auth_user_id_rls.sql`). Every membership-gated policy MUST go through it; never re-derive the membership predicate inline.
  - When a policy needs the caller's `device_fp` (e.g. `written_by_device` guard, `device_sync_cursors`), look it up via `SELECT device_fp FROM family_devices WHERE auth_user_id = auth.uid() AND family_id = … AND revoked_at IS NULL LIMIT 1` — see `0017_rls_reharden.sql` for the pattern.
  - This anti-pattern shipped in `0002_rls.sql` and was only fully retired in `0026_fix_families_select_uuid_send_bug.sql` after 5 partial fixes (0010, 0011, 0014, 0016, 0017). Reference 0026 when reviewing new RLS or SECURITY DEFINER code.

## Folder structure
- `/lib/features/onboarding`, `/home`, `/feed`, `/pump`, `/diaper`, `/sleep`, `/stash`, `/share`, `/summary`, `/vaccination`, `/visit_report`, `/subscription`, `/settings`, `/dreambaby_bridge`
- `/lib/core/theme`, `/db`, `/sync`, `/crypto`, `/router`, `/services`, `/providers`, `/l10n`
- `/lib/l10n/app_en.arb` + `/app_th.arb` → `flutter gen-l10n` outputs to `/lib/l10n/generated/` (git-ignored)

## Plan roadmap
- **Plan A** (this branch) — Foundation: scaffold, theme, L10n, DB v1, secure key, router, Home shell, Share invite placeholder, Welcome
- **Plan B** — Local logging: Feed/Pump/Stash/Diaper/Sleep CRUD + Daily Summary (offline only). Reintroduces freezed + codegen when compatible.
- **Plan C** — Sync + Crypto: Supabase, AES-GCM, invite code generation, caregiver onboarding
- **Plan D** — Premium: Multi-baby, RevenueCat, paywall
- **Plan E** — Clinical: Vaccination log, Visit Summary PDF
- **Plan F** — Polish + DreamBaby bridge, L10n review, QA, beta

## Verification commands
- `flutter analyze` — must pass
- `flutter test` — must pass
- `flutter build apk --debug` — must produce APK (currently DEFERRED: Android cmdline-tools missing + licenses unset)
- `tool/check_no_exact_alarms.sh` — must say OK
- `flutter gen-l10n` — regenerates `lib/l10n/generated/` after ARB edits

## Toolchain state (as of 2026-05-13)
- Flutter 3.41.9 stable / Dart 3.11.5 — OK
- Android SDK 36.1.0 BUT `cmdline-tools` missing + licenses not accepted — APK builds blocked until user runs: install via Android Studio SDK Manager → check Android SDK Command-line Tools → then `flutter doctor --android-licenses` and accept all
- CocoaPods NOT installed — iOS pod install blocked until `sudo gem install cocoapods` (defer; iOS launches months after Android)
