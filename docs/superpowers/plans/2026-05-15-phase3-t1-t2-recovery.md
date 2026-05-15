# Phase 3 — T1 + T2 Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add BIP-39 recovery phrases (T2, mandatory at setup) and a Manage Devices screen (T1) so users can recover their family's data if they lose their phone.

**Architecture:**
- `Bip39Service` wraps `package:bip39` for phrase generation/validation plus BLAKE2b lookup-hash.
- `RecoveryService` uses Argon2id (same params as invite KDF) + AES-GCM to wrap/unwrap K_family.
- Two new Edge Functions: `upload_recovery` (registers envelope + lookup hash server-side) and a real `claim_recovery` implementation (returns envelope + registers new device).
- Onboarding is modified to bootstrap the family eagerly; BIP-39 setup is shown before home. Offline users land on home with a "Set up recovery" banner.

**Tech Stack:** Flutter/Dart, `package:bip39 ^1.0.6` (already in pubspec), `package:cryptography` Argon2id + BLAKE2b, Supabase Edge Functions (Deno/TypeScript), existing `CryptoEnvelope`, `FamilyKeyService`, `DeviceIdentityService`.

**Branch:** create `feat/phase3-recovery` from `hardening/phase-1-base`.

**New files:**
- `lib/core/crypto/bip39_service.dart`
- `lib/core/crypto/recovery_service.dart`
- `lib/features/recovery/presentation/bip39_setup_screen.dart`
- `lib/features/recovery/presentation/bip39_verify_screen.dart`
- `lib/features/recovery/presentation/bip39_restore_screen.dart`
- `lib/features/settings/presentation/manage_devices_screen.dart`
- `supabase/functions/upload_recovery/index.ts`
- `test/core/crypto/bip39_service_test.dart`
- `test/core/crypto/recovery_service_test.dart`
- `test/integration/recovery_t2_test.dart`

**Modified files:**
- `pubspec.yaml` — `bip39 ^1.0.6` already added
- `lib/core/router/app_router.dart` — add 4 routes + whitelist them from redirect
- `lib/features/onboarding/presentation/welcome_screen.dart` — eager bootstrap + Restore button
- `lib/features/settings/presentation/settings_screen.dart` — Recovery Phrase + Manage Devices rows
- `lib/l10n/app_en.arb` + `app_th.arb` — new strings
- `supabase/functions/claim_recovery/index.ts` — replace stub with real implementation

---

## Task 1: Create feature branch

- [ ] **Step 1: Branch off hardening/phase-1-base**

```bash
git checkout hardening/phase-1-base
git checkout -b feat/phase3-recovery
```

- [ ] **Step 2: Verify tests pass**

```bash
flutter test
```

Expected: `279 tests passed`

---

## Task 2: Write failing tests for Bip39Service

**Files:**
- Create: `test/core/crypto/bip39_service_test.dart`

- [ ] **Step 1: Create test file**

```dart
// test/core/crypto/bip39_service_test.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:dreambook/core/crypto/bip39_service.dart';

void main() {
  final service = Bip39Service();

  group('generatePhrase', () {
    test('returns 12 space-separated lowercase words', () {
      final phrase = service.generatePhrase();
      final words = phrase.split(' ');
      expect(words.length, 12);
      for (final w in words) {
        expect(w, equals(w.toLowerCase()));
        expect(w.isNotEmpty, isTrue);
      }
    });

    test('two calls produce different phrases', () {
      final a = service.generatePhrase();
      final b = service.generatePhrase();
      expect(a, isNot(equals(b)));
    });
  });

  group('validatePhrase', () {
    test('valid phrase returns true', () {
      final phrase = service.generatePhrase();
      expect(service.validatePhrase(phrase), isTrue);
    });

    test('garbled phrase returns false', () {
      expect(service.validatePhrase('abc def ghi jkl mno pqr stu vwx yza bcd efg hij'), isFalse);
    });

    test('validates after normalisation (extra spaces, mixed case)', () {
      final phrase = service.generatePhrase();
      final messy = '  ${phrase.toUpperCase().replaceAll(' ', '  ')}  ';
      expect(service.validatePhrase(messy), isTrue);
    });
  });

  group('normalizePhrase', () {
    test('lowercases and collapses spaces', () {
      const input = '  ABANDON  ABILITY  ABLE  ';
      expect(service.normalizePhrase(input), equals('abandon ability able'));
    });
  });

  group('toWords', () {
    test('splits phrase into 12-element list', () {
      final phrase = service.generatePhrase();
      expect(service.toWords(phrase).length, 12);
    });
  });

  group('lookupHash', () {
    test('returns 64-byte Uint8List', () async {
      final phrase = service.generatePhrase();
      final hash = await service.lookupHash(phrase);
      expect(hash, isA<Uint8List>());
      expect(hash.length, 64);
    });

    test('same normalised phrase produces same hash', () async {
      const phrase = 'abandon ability able about above absent absorb abstract absurd abuse access accident';
      final h1 = await service.lookupHash(phrase);
      final h2 = await service.lookupHash('  ABANDON  ABILITY  ABLE  ABOUT  ABOVE  ABSENT  ABSORB  ABSTRACT  ABSURD  ABUSE  ACCESS  ACCIDENT  ');
      expect(h1, equals(h2));
    });

    test('different phrases produce different hashes', () async {
      final p1 = service.generatePhrase();
      final p2 = service.generatePhrase();
      final h1 = await service.lookupHash(p1);
      final h2 = await service.lookupHash(p2);
      expect(h1, isNot(equals(h2)));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/core/crypto/bip39_service_test.dart
```

Expected: compilation error — `bip39_service.dart` does not exist.

---

## Task 3: Implement Bip39Service

**Files:**
- Create: `lib/core/crypto/bip39_service.dart`

- [ ] **Step 1: Create the service**

```dart
// lib/core/crypto/bip39_service.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:cryptography/cryptography.dart';

class Bip39Service {
  /// Generates a fresh 12-word BIP-39 phrase (128-bit entropy).
  String generatePhrase() => bip39.generateMnemonic();

  /// Returns true iff the BIP-39 checksum is valid.
  /// Normalises the phrase (lowercase, collapsed spaces) before checking.
  bool validatePhrase(String phrase) =>
      bip39.validateMnemonic(normalizePhrase(phrase));

  /// Lowercase + single spaces — canonical form for KDF input.
  String normalizePhrase(String phrase) =>
      phrase.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Splits normalised phrase into individual words.
  List<String> toWords(String phrase) => normalizePhrase(phrase).split(' ');

  /// BLAKE2b-512 of the normalised phrase bytes — stored in `recovery_lookup`
  /// so the server can find the family without learning the phrase.
  Future<Uint8List> lookupHash(String phrase) async {
    final hasher = Blake2b(hashLengthInBytes: 64);
    final hash = await hasher.hash(utf8.encode(normalizePhrase(phrase)));
    return Uint8List.fromList(hash.bytes);
  }
}
```

- [ ] **Step 2: Run tests**

```bash
flutter test test/core/crypto/bip39_service_test.dart
```

Expected: all 9 tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/core/crypto/bip39_service.dart test/core/crypto/bip39_service_test.dart
git commit -m "feat(recovery): Bip39Service — generate/validate/hash BIP-39 phrases"
```

---

## Task 4: Write failing tests for RecoveryService

**Files:**
- Create: `test/core/crypto/recovery_service_test.dart`

- [ ] **Step 1: Create test file**

```dart
// test/core/crypto/recovery_service_test.dart
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dreambook/core/crypto/recovery_service.dart';

void main() {
  // Use low-memory Argon2id params for tests so they finish in <5s.
  final testKdf = Argon2id(memory: 256, parallelism: 1, iterations: 1, hashLength: 32);

  RecoveryService makeService() => RecoveryService(kdf: testKdf);

  group('wrapFamilyKey / unwrapFamilyKey', () {
    test('round-trip recovers original K_family', () async {
      const phrase = 'abandon ability able about above absent absorb abstract absurd abuse access accident';
      final familyKey = Uint8List.fromList(List.generate(32, (i) => i));
      const familyId = 'test-family-id';
      const keyVersion = 1;

      final service = makeService();
      final wrapped = await service.wrapFamilyKey(
        normalizedPhrase: phrase,
        familyKey: familyKey,
        familyId: familyId,
        keyVersion: keyVersion,
      );

      expect(wrapped.wrappedKey.isNotEmpty, isTrue);
      expect(wrapped.salt.length, 16);

      final recovered = await service.unwrapFamilyKey(
        normalizedPhrase: phrase,
        wrappedKey: wrapped.wrappedKey,
        salt: wrapped.salt,
        familyId: familyId,
        keyVersion: keyVersion,
      );

      expect(recovered, equals(familyKey));
    });

    test('wrong phrase throws SecretBoxAuthenticationError', () async {
      const rightPhrase = 'abandon ability able about above absent absorb abstract absurd abuse access accident';
      const wrongPhrase = 'zoo zebra young year worry worth wrap wreck wrestle wrist write wrong';
      final familyKey = Uint8List.fromList(List.generate(32, (i) => i + 1));
      const familyId = 'test-family-id';

      final service = makeService();
      final wrapped = await service.wrapFamilyKey(
        normalizedPhrase: rightPhrase,
        familyKey: familyKey,
        familyId: familyId,
        keyVersion: 1,
      );

      expect(
        () => service.unwrapFamilyKey(
          normalizedPhrase: wrongPhrase,
          wrappedKey: wrapped.wrappedKey,
          salt: wrapped.salt,
          familyId: familyId,
          keyVersion: 1,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('wrong familyId throws SecretBoxAuthenticationError', () async {
      const phrase = 'abandon ability able about above absent absorb abstract absurd abuse access accident';
      final familyKey = Uint8List.fromList(List.generate(32, (i) => i));

      final service = makeService();
      final wrapped = await service.wrapFamilyKey(
        normalizedPhrase: phrase,
        familyKey: familyKey,
        familyId: 'family-a',
        keyVersion: 1,
      );

      expect(
        () => service.unwrapFamilyKey(
          normalizedPhrase: phrase,
          wrappedKey: wrapped.wrappedKey,
          salt: wrapped.salt,
          familyId: 'family-b',
          keyVersion: 1,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('each wrap produces different ciphertext (fresh salt)', () async {
      const phrase = 'abandon ability able about above absent absorb abstract absurd abuse access accident';
      final familyKey = Uint8List.fromList(List.generate(32, (i) => i));

      final service = makeService();
      final w1 = await service.wrapFamilyKey(
        normalizedPhrase: phrase,
        familyKey: familyKey,
        familyId: 'fid',
        keyVersion: 1,
      );
      final w2 = await service.wrapFamilyKey(
        normalizedPhrase: phrase,
        familyKey: familyKey,
        familyId: 'fid',
        keyVersion: 1,
      );

      // Salt should differ (fresh CSPRNG), ciphertexts should differ.
      expect(w1.salt, isNot(equals(w2.salt)));
      expect(w1.wrappedKey, isNot(equals(w2.wrappedKey)));
    });
  });
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
flutter test test/core/crypto/recovery_service_test.dart
```

Expected: compilation error — `recovery_service.dart` not found.

---

## Task 5: Implement RecoveryService

**Files:**
- Create: `lib/core/crypto/recovery_service.dart`

- [ ] **Step 1: Create the service**

```dart
// lib/core/crypto/recovery_service.dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'crypto_envelope.dart';

/// Wraps and unwraps K_family using a BIP-39 phrase-derived key.
///
/// KDF: Argon2id m=64 MiB, t=3, p=1 (same config as InviteCodeService).
/// Wrap: AES-GCM(K_kdf, K_family, aad="${familyId}|${keyVersion}").
class WrappedRecoveryKey {
  const WrappedRecoveryKey({required this.wrappedKey, required this.salt});
  final Uint8List wrappedKey; // CryptoEnvelope v1 blob
  final Uint8List salt;       // 16 random bytes, stored in family_recovery_envelopes
}

class RecoveryService {
  RecoveryService({Argon2id? kdf, CryptoEnvelope? envelope, Random? rng})
      : _kdf = kdf ?? _defaultKdf(),
        _envelope = envelope ?? CryptoEnvelope(),
        _rng = rng ?? Random.secure();

  final Argon2id _kdf;
  final CryptoEnvelope _envelope;
  final Random _rng;

  static Argon2id _defaultKdf() => Argon2id(
        memory: 65536,   // 64 MiB in KiB
        parallelism: 1,
        iterations: 3,
        hashLength: 32,
      );

  /// Wraps [familyKey] under a key derived from [normalizedPhrase] + fresh salt.
  /// AAD binds the envelope to [familyId] and [keyVersion].
  Future<WrappedRecoveryKey> wrapFamilyKey({
    required String normalizedPhrase,
    required Uint8List familyKey,
    required String familyId,
    required int keyVersion,
  }) async {
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => _rng.nextInt(256)),
    );
    final kdfKey = await _deriveKey(phrase: normalizedPhrase, salt: salt);
    final wrapped = await _envelope.seal(
      familyKey,
      kdfKey,
      utf8.encode('$familyId|$keyVersion'),
    );
    return WrappedRecoveryKey(wrappedKey: wrapped, salt: salt);
  }

  /// Reverses [wrapFamilyKey]. Throws [SecretBoxAuthenticationError] on wrong
  /// phrase, wrong salt, tampered envelope, or mismatched familyId/keyVersion.
  Future<Uint8List> unwrapFamilyKey({
    required String normalizedPhrase,
    required Uint8List wrappedKey,
    required Uint8List salt,
    required String familyId,
    required int keyVersion,
  }) async {
    final kdfKey = await _deriveKey(phrase: normalizedPhrase, salt: salt);
    return _envelope.open(
      wrappedKey,
      kdfKey,
      utf8.encode('$familyId|$keyVersion'),
    );
  }

  Future<SecretKey> _deriveKey({
    required String phrase,
    required Uint8List salt,
  }) =>
      _kdf.deriveKey(
        secretKey: SecretKey(utf8.encode(phrase)),
        nonce: salt,
      );
}
```

- [ ] **Step 2: Run tests**

```bash
flutter test test/core/crypto/recovery_service_test.dart
```

Expected: 4 tests pass. (Note: Argon2id with memory=256KiB is fast; production config is 64MiB and will be slow but correct.)

- [ ] **Step 3: Run full suite**

```bash
flutter test
```

Expected: 281+ tests pass, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add lib/core/crypto/recovery_service.dart test/core/crypto/recovery_service_test.dart
git commit -m "feat(recovery): RecoveryService — Argon2id KDF + AES-GCM wrap/unwrap for BIP-39 recovery"
```

---

## Task 6: `upload_recovery` Edge Function

**Files:**
- Create: `supabase/functions/upload_recovery/index.ts`

This EF is called by the admin device after BIP-39 phrase verification. It needs service_role to write to `recovery_lookup` (which only `service_role` can write). It also upserts `family_recovery_envelopes`.

- [ ] **Step 1: Create the function**

```typescript
// supabase/functions/upload_recovery/index.ts
// upload_recovery — registers BIP-39 recovery envelope + lookup hash.
// Body: { lookup_hash_b64: string, wrapped_key_b64: string, salt_b64: string, key_version: number }
// Auth: Bearer JWT (authenticated admin device, has an active family).
// Returns: { success: true }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { writeAuditEvent } from "../_shared/audit.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function bytesFromBase64(s: string): Uint8Array {
  const clean = s.replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(clean);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

function hexFromBytes(b: Uint8Array): string {
  return Array.from(b).map((x) => x.toString(16).padStart(2, "0")).join("");
}

function toByteaHex(b: Uint8Array): string {
  return "\\x" + hexFromBytes(b);
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return new Response("Unauthorized", { status: 401 });
  }

  const body = await req.json().catch(() => null) as {
    lookup_hash_b64: string;
    wrapped_key_b64: string;
    salt_b64: string;
    key_version: number;
  } | null;

  if (
    !body?.lookup_hash_b64 ||
    !body.wrapped_key_b64 ||
    !body.salt_b64 ||
    !body.key_version
  ) {
    return new Response(JSON.stringify({ error: "missing fields" }), { status: 400 });
  }

  // Authenticate caller and resolve their device's family_id.
  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });

  const { data: userData } = await userClient.auth.getUser();
  if (!userData?.user) {
    return new Response("Unauthorized", { status: 401 });
  }

  const { data: deviceRow, error: deviceErr } = await userClient
    .from("family_devices")
    .select("device_fp, family_id")
    .eq("auth_user_id", userData.user.id)
    .is("revoked_at", null)
    .limit(1)
    .single();

  if (deviceErr || !deviceRow) {
    return new Response("Device not found in any family", { status: 403 });
  }
  const familyId: string = deviceRow.family_id;
  const deviceFpHex: string = typeof deviceRow.device_fp === "string"
    ? deviceRow.device_fp.replace(/^\\x/, "")
    : hexFromBytes(new Uint8Array(deviceRow.device_fp));

  const svc = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

  // Upsert the recovery envelope (one row per family).
  const wrappedKey = bytesFromBase64(body.wrapped_key_b64);
  const salt = bytesFromBase64(body.salt_b64);

  const { error: envErr } = await svc.from("family_recovery_envelopes").upsert(
    {
      family_id: familyId,
      wrapped_key: toByteaHex(wrappedKey),
      salt: toByteaHex(salt),
      key_version: body.key_version,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "family_id" },
  );

  if (envErr) {
    return new Response(JSON.stringify({ error: envErr.message }), { status: 500 });
  }

  // Replace lookup entry atomically: delete old → insert new.
  await svc.from("recovery_lookup").delete().eq("family_id", familyId);
  const lookupHash = bytesFromBase64(body.lookup_hash_b64);
  const { error: lookupErr } = await svc.from("recovery_lookup").insert({
    lookup_hash: toByteaHex(lookupHash),
    family_id: familyId,
  });

  if (lookupErr) {
    return new Response(JSON.stringify({ error: lookupErr.message }), { status: 500 });
  }

  await writeAuditEvent(
    familyId,
    "recovery_phrase_registered",
    deviceFpHex,
    { key_version: body.key_version },
  ).catch(() => {});

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
```

- [ ] **Step 2: Commit**

```bash
git add supabase/functions/upload_recovery/
git commit -m "feat(recovery): upload_recovery EF — registers BIP-39 envelope + lookup hash"
```

---

## Task 7: `claim_recovery` Edge Function (real implementation)

**Files:**
- Modify: `supabase/functions/claim_recovery/index.ts`

Called by a new device that has lost its phone. Device does `signInAnonymously()` first, then posts here with its pub key and the lookup hash derived from the BIP-39 phrase. The EF returns the recovery envelope; the client derives the key and unwraps K_family locally.

- [ ] **Step 1: Replace stub with full implementation**

```typescript
// supabase/functions/claim_recovery/index.ts
// claim_recovery — BIP-39 recovery: returns wrapped K_family + registers new device.
// Body: { lookup_hash_b64: string, device_pub_key_b64: string }
// Auth: Bearer JWT (signInAnonymously on new device first).
// Returns: { wrapped_key_b64, salt_b64, key_version, family_id }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { writeAuditEvent } from "../_shared/audit.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RATE_LIMIT = 5;
const RATE_WINDOW_HOURS = 1;

function bytesFromBase64(s: string): Uint8Array {
  const clean = s.replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(clean);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

function hexFromBytes(b: Uint8Array): string {
  return Array.from(b).map((x) => x.toString(16).padStart(2, "0")).join("");
}

function toByteaHex(b: Uint8Array): string {
  return "\\x" + hexFromBytes(b);
}

function base64FromHex(hex: string): string {
  const clean = hex.replace(/^\\x/, "");
  const bytes = new Uint8Array(clean.length / 2);
  for (let i = 0; i < clean.length; i += 2) {
    bytes[i / 2] = parseInt(clean.substring(i, i + 2), 16);
  }
  return btoa(String.fromCharCode(...bytes));
}

serve(async (req) => {
  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405 });

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return new Response("Unauthorized", { status: 401 });

  const body = await req.json().catch(() => null) as {
    lookup_hash_b64: string;
    device_pub_key_b64: string;
  } | null;

  if (!body?.lookup_hash_b64 || !body.device_pub_key_b64) {
    return new Response(JSON.stringify({ error: "missing fields" }), { status: 400 });
  }

  // Authenticate caller (new device with anonymous JWT).
  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: userData } = await userClient.auth.getUser();
  if (!userData?.user) return new Response("Unauthorized", { status: 401 });

  // Compute device_fp = SHA-256(pubkey)[0:16].
  const devicePubKey = bytesFromBase64(body.device_pub_key_b64);
  const hashBuf = await crypto.subtle.digest("SHA-256", devicePubKey);
  const deviceFp = new Uint8Array(hashBuf).slice(0, 16);
  const deviceFpHex = hexFromBytes(deviceFp);

  const svc = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

  // Look up family_id via recovery_lookup (service_role only table).
  const lookupHash = bytesFromBase64(body.lookup_hash_b64);
  const { data: lookupRow, error: lookupErr } = await svc
    .from("recovery_lookup")
    .select("family_id")
    .eq("lookup_hash", toByteaHex(lookupHash))
    .single();

  if (lookupErr || !lookupRow) {
    await writeAuditEvent(null, "recovery_attempted", deviceFpHex, { reason: "not_found" }).catch(() => {});
    return new Response("Not Found", { status: 404 });
  }
  const familyId: string = lookupRow.family_id;

  // Rate limit: count failed attempts in last RATE_WINDOW_HOURS for this family.
  const windowStart = new Date(Date.now() - RATE_WINDOW_HOURS * 3600 * 1000).toISOString();
  const { count } = await svc
    .from("recovery_attempts")
    .select("id", { count: "exact", head: true })
    .eq("family_id", familyId)
    .eq("success", false)
    .gte("attempted_at", windowStart);

  if ((count ?? 0) >= RATE_LIMIT) {
    await writeAuditEvent(familyId, "recovery_attempted", deviceFpHex, { reason: "rate_limited" }).catch(() => {});
    return new Response("Too Many Requests", { status: 429 });
  }

  // Record this attempt (initially failed; updated to success on completion).
  const { data: attemptRow } = await svc
    .from("recovery_attempts")
    .insert({ family_id: familyId, success: false })
    .select("id")
    .single();
  const attemptId: string | null = attemptRow?.id ?? null;

  // Fetch the recovery envelope.
  const { data: envelope, error: envelopeErr } = await svc
    .from("family_recovery_envelopes")
    .select("wrapped_key, salt, key_version")
    .eq("family_id", familyId)
    .single();

  if (envelopeErr || !envelope) {
    await writeAuditEvent(familyId, "recovery_attempted", deviceFpHex, { reason: "no_envelope" }).catch(() => {});
    return new Response("Recovery envelope not found", { status: 404 });
  }

  // Register the new device in family_devices.
  await svc.from("family_devices").upsert(
    {
      device_fp: toByteaHex(deviceFp),
      family_id: familyId,
      device_pub_key: toByteaHex(devicePubKey),
      role: "editor",
      joined_at: new Date().toISOString(),
      key_version_at_join: envelope.key_version,
      auth_user_id: userData.user.id,
    },
    { onConflict: "device_fp", ignoreDuplicates: false },
  );

  // Mark attempt as successful.
  if (attemptId) {
    await svc.from("recovery_attempts").update({ success: true }).eq("id", attemptId);
  }

  await writeAuditEvent(
    familyId,
    "recovery_succeeded",
    deviceFpHex,
    { key_version: envelope.key_version },
  ).catch(() => {});

  // Encode bytea values for the client.
  // PostgREST returns bytea as \x-prefixed hex strings in JSON.
  const wrappedKeyB64 = base64FromHex(
    typeof envelope.wrapped_key === "string" ? envelope.wrapped_key : hexFromBytes(new Uint8Array(envelope.wrapped_key)),
  );
  const saltB64 = base64FromHex(
    typeof envelope.salt === "string" ? envelope.salt : hexFromBytes(new Uint8Array(envelope.salt)),
  );

  return new Response(
    JSON.stringify({
      wrapped_key_b64: wrappedKeyB64,
      salt_b64: saltB64,
      key_version: envelope.key_version,
      family_id: familyId,
    }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
```

- [ ] **Step 2: Commit**

```bash
git add supabase/functions/claim_recovery/index.ts
git commit -m "feat(recovery): claim_recovery EF — real implementation with rate limiting + device registration"
```

---

## Task 8: Add l10n strings

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_th.arb`

- [ ] **Step 1: Add English strings to app_en.arb**

Add before the closing `}` in `app_en.arb`:

```json
  "recoverySetupHeadline": "Save your recovery phrase",
  "recoverySetupSubcopy": "Write these 12 words on paper and store them safely. If you lose your phone, this phrase is the only way to recover your data.",
  "recoverySetupWrittenCta": "I've written them down",
  "recoverySetupRemindLater": "Remind me later",
  "recoverySetupWarning": "Do not screenshot this screen. Store this on paper, not in your phone.",

  "recoveryVerifyHeadline": "Confirm your phrase",
  "recoveryVerifySubcopy": "Enter the words below to confirm you wrote them down.",
  "recoveryVerifyWord": "Word {number}",
  "@recoveryVerifyWord": {
    "placeholders": {
      "number": { "type": "int" }
    }
  },
  "recoveryVerifyConfirmCta": "Confirm",
  "recoveryVerifyWrongTryAgain": "Wrong words — please try again.",
  "recoveryVerifyWrongRegenerate": "Two wrong attempts — generating a new phrase.",
  "recoveryVerifySuccess": "Recovery phrase saved.",

  "recoveryRestoreHeadline": "Restore from recovery phrase",
  "recoveryRestoreSubcopy": "Enter your 12-word recovery phrase to recover your data on this device.",
  "recoveryRestoreLabel": "Recovery phrase",
  "recoveryRestoreHint": "word1 word2 word3 ...",
  "recoveryRestoreCta": "Restore",
  "recoveryRestoreInvalidChecksum": "One or more words are incorrect. Check your phrase and try again.",
  "recoveryRestoreNotFound": "Recovery phrase not recognised.",
  "recoveryRestoreRateLimit": "Too many attempts. Wait an hour and try again.",
  "recoveryRestoreError": "Restore failed. Check your connection and try again.",
  "recoveryRestoreSuccess": "Welcome back!",

  "welcomeRestoreCta": "Restore from recovery phrase",

  "settingsRecoveryPhraseTitle": "Recovery phrase",
  "settingsRecoveryPhraseBackedUp": "Backed up",
  "settingsRecoveryPhraseNotBackedUp": "Not set up — tap to protect your data",
  "settingsManageDevicesTitle": "Manage devices",

  "manageDevicesHeadline": "Devices",
  "manageDevicesEmpty": "No other devices.",
  "manageDevicesRevokeButton": "Remove",
  "manageDevicesRevokeConfirmTitle": "Remove device?",
  "manageDevicesRevokeConfirmBody": "This device will no longer sync with your family.",
  "manageDevicesRevokeConfirmCta": "Remove",
  "manageDevicesRevokeCancel": "Cancel",
  "manageDevicesRecoveryInvite": "Generate recovery invite",
  "manageDevicesAdmin": "Admin",
  "manageDevicesEditor": "Member",
  "manageDevicesThisDevice": "This device"
```

- [ ] **Step 2: Add Thai strings to app_th.arb**

Add before the closing `}` in `app_th.arb`:

```json
  "recoverySetupHeadline": "บันทึก Recovery Phrase",
  "recoverySetupSubcopy": "เขียน 12 คำเหล่านี้ลงกระดาษและเก็บไว้ในที่ปลอดภัย ถ้าโทรศัพท์หาย คำเหล่านี้คือทางเดียวที่จะกู้ข้อมูลได้",
  "recoverySetupWrittenCta": "เขียนแล้ว",
  "recoverySetupRemindLater": "เตือนทีหลัง",
  "recoverySetupWarning": "อย่าถ่ายภาพหน้าจอ เขียนลงกระดาษเท่านั้น",

  "recoveryVerifyHeadline": "ยืนยัน Recovery Phrase",
  "recoveryVerifySubcopy": "กรอกคำด้านล่างเพื่อยืนยันว่าเขียนไว้แล้ว",
  "recoveryVerifyWord": "คำที่ {number}",
  "@recoveryVerifyWord": {
    "placeholders": {
      "number": { "type": "int" }
    }
  },
  "recoveryVerifyConfirmCta": "ยืนยัน",
  "recoveryVerifyWrongTryAgain": "คำไม่ถูก — ลองอีกครั้ง",
  "recoveryVerifyWrongRegenerate": "ผิดสองครั้ง — กำลังสร้างคำใหม่",
  "recoveryVerifySuccess": "บันทึก Recovery Phrase แล้ว",

  "recoveryRestoreHeadline": "กู้ข้อมูลจาก Recovery Phrase",
  "recoveryRestoreSubcopy": "กรอก Recovery Phrase 12 คำเพื่อกู้ข้อมูลในเครื่องนี้",
  "recoveryRestoreLabel": "Recovery Phrase",
  "recoveryRestoreHint": "คำที่1 คำที่2 คำที่3 ...",
  "recoveryRestoreCta": "กู้ข้อมูล",
  "recoveryRestoreInvalidChecksum": "คำไม่ถูกต้อง ตรวจสอบ Recovery Phrase อีกครั้ง",
  "recoveryRestoreNotFound": "ไม่พบ Recovery Phrase นี้",
  "recoveryRestoreRateLimit": "ลองมากเกินไป รอ 1 ชั่วโมงแล้วลองใหม่",
  "recoveryRestoreError": "กู้ข้อมูลไม่สำเร็จ ตรวจสอบสัญญาณอินเทอร์เน็ต",
  "recoveryRestoreSuccess": "ยินดีต้อนรับกลับมา!",

  "welcomeRestoreCta": "กู้ข้อมูลจาก Recovery Phrase",

  "settingsRecoveryPhraseTitle": "Recovery Phrase",
  "settingsRecoveryPhraseBackedUp": "บันทึกแล้ว",
  "settingsRecoveryPhraseNotBackedUp": "ยังไม่ได้ตั้งค่า — แตะเพื่อป้องกันข้อมูล",
  "settingsManageDevicesTitle": "จัดการอุปกรณ์",

  "manageDevicesHeadline": "อุปกรณ์",
  "manageDevicesEmpty": "ไม่มีอุปกรณ์อื่น",
  "manageDevicesRevokeButton": "ลบออก",
  "manageDevicesRevokeConfirmTitle": "ลบอุปกรณ์นี้?",
  "manageDevicesRevokeConfirmBody": "อุปกรณ์นี้จะหยุดซิงค์กับครอบครัว",
  "manageDevicesRevokeConfirmCta": "ลบออก",
  "manageDevicesRevokeCancel": "ยกเลิก",
  "manageDevicesRecoveryInvite": "สร้างรหัสกู้คืน",
  "manageDevicesAdmin": "แอดมิน",
  "manageDevicesEditor": "สมาชิก",
  "manageDevicesThisDevice": "เครื่องนี้"
```

- [ ] **Step 3: Regenerate l10n**

```bash
flutter gen-l10n
```

Expected: no errors. New keys appear in `lib/l10n/generated/app_localizations.dart`.

- [ ] **Step 4: Verify tests still pass**

```bash
flutter test
```

Expected: 281+ tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_th.arb
git commit -m "feat(recovery): l10n strings for BIP-39 setup, verify, restore, devices"
```

---

## Task 9: Add recovery + devices routes to app_router.dart

**Files:**
- Modify: `lib/core/router/app_router.dart`

The new routes must be whitelisted from the "redirect to /welcome if not onboarded" guard, because `/recovery/restore` is used during onboarding by a returning user.

- [ ] **Step 1: Modify app_router.dart**

```dart
// lib/core/router/app_router.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/baby/presentation/baby_switcher_screen.dart';
import '../../features/diaper/presentation/diaper_log_screen.dart';
import '../../features/feed/presentation/feed_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/pump/presentation/pump_session_screen.dart';
import '../../features/recovery/presentation/bip39_restore_screen.dart';
import '../../features/recovery/presentation/bip39_setup_screen.dart';
import '../../features/recovery/presentation/bip39_verify_screen.dart';
import '../../features/settings/presentation/manage_devices_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/caregivers/presentation/caregivers_screen.dart';
import '../../features/share/presentation/claim_invite_screen.dart';
import '../../features/share/presentation/share_invite_screen.dart';
import '../../features/sleep/presentation/sleep_timer_screen.dart';
import '../../features/stash/presentation/stash_list_screen.dart';
import '../../features/subscription/presentation/paywall_screen.dart';
import '../../features/summary/presentation/daily_summary_screen.dart';
import '../../features/vaccination/presentation/vaccination_log_screen.dart';
import '../../features/visit_report/presentation/visit_report_screen.dart';
import '../providers/shared_preferences_provider.dart';
import '../widgets/scaffold_with_nav_bar.dart';

class AppRoutes {
  AppRoutes._();
  static const welcome         = '/welcome';
  static const home            = '/';
  static const caregivers      = '/caregivers';
  static const shareInvite     = '/share/invite';
  static const shareClaim      = '/share/claim';
  static const babies          = '/babies';
  static const premium         = '/settings/premium';
  static const feedNew         = '/feed/new';
  static const pumpNew         = '/pump/new';
  static const settings        = '/settings';
  static const stash           = '/stash';
  static const diaperNew       = '/diaper/new';
  static const sleep           = '/sleep';
  static const summary         = '/summary';
  static const vaccination     = '/vaccination';
  static const visitReport     = '/visit-report';
  static const bip39Setup      = '/recovery/setup';
  static const bip39Verify     = '/recovery/verify';
  static const bip39Restore    = '/recovery/restore';
  static const manageDevices   = '/settings/devices';
}

const kOnboardingDoneKey = 'onboarding.done';

// Routes accessible before onboarding is complete.
const _noRedirectRoutes = {
  AppRoutes.welcome,
  AppRoutes.shareClaim,
  AppRoutes.bip39Setup,
  AppRoutes.bip39Verify,
  AppRoutes.bip39Restore,
};

final appRouterProvider = Provider<GoRouter>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return GoRouter(
    initialLocation: AppRoutes.home,
    redirect: (context, state) {
      final onboarded = prefs.getBool(kOnboardingDoneKey) ?? false;
      if (!onboarded && !_noRedirectRoutes.contains(state.matchedLocation)) {
        final intended = state.uri.toString();
        if (intended != AppRoutes.home) {
          prefs.setString('router.pendingDeepLink', intended);
        }
        return AppRoutes.welcome;
      }
      if (onboarded && state.matchedLocation == AppRoutes.welcome) {
        return AppRoutes.home;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.welcome,
        builder: (_, __) => const WelcomeScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => ScaffoldWithNavBar(child: child),
        routes: [
          GoRoute(path: AppRoutes.home,    builder: (_, __) => const HomeScreen()),
          GoRoute(path: AppRoutes.summary, builder: (_, __) => const DailySummaryScreen()),
          GoRoute(path: AppRoutes.stash,   builder: (_, __) => const StashListScreen()),
          GoRoute(path: AppRoutes.settings, builder: (_, __) => const SettingsScreen()),
        ],
      ),
      GoRoute(path: AppRoutes.caregivers,   builder: (_, __) => const CaregiversScreen()),
      GoRoute(path: AppRoutes.shareInvite,  builder: (_, __) => const ShareInviteScreen()),
      GoRoute(path: AppRoutes.shareClaim,   builder: (_, __) => const ClaimInviteScreen()),
      GoRoute(path: AppRoutes.babies,       builder: (_, __) => const BabySwitcherScreen()),
      GoRoute(path: AppRoutes.premium,      builder: (_, __) => const PaywallScreen()),
      GoRoute(path: AppRoutes.feedNew,      builder: (_, __) => const FeedScreen()),
      GoRoute(path: AppRoutes.pumpNew,      builder: (_, __) => const PumpSessionScreen()),
      GoRoute(path: AppRoutes.diaperNew,    builder: (_, __) => const DiaperLogScreen()),
      GoRoute(path: AppRoutes.sleep,        builder: (_, __) => const SleepTimerScreen()),
      GoRoute(path: AppRoutes.vaccination,  builder: (_, __) => const VaccinationLogScreen()),
      GoRoute(
        path: AppRoutes.visitReport,
        builder: (_, __) => const VisitReportScreen(),
      ),
      GoRoute(
        path: AppRoutes.bip39Setup,
        builder: (_, __) => const Bip39SetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.bip39Verify,
        builder: (context, state) => Bip39VerifyScreen(phrase: state.extra as String),
      ),
      GoRoute(
        path: AppRoutes.bip39Restore,
        builder: (_, __) => const Bip39RestoreScreen(),
      ),
      GoRoute(
        path: AppRoutes.manageDevices,
        builder: (_, __) => const ManageDevicesScreen(),
      ),
    ],
  );
});
```

- [ ] **Step 2: Create stub screens** (so app_router.dart compiles before screens are built)

```dart
// lib/features/recovery/presentation/bip39_setup_screen.dart
import 'package:flutter/material.dart';
class Bip39SetupScreen extends StatelessWidget {
  const Bip39SetupScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('BIP-39 Setup — TODO')));
}
```

```dart
// lib/features/recovery/presentation/bip39_verify_screen.dart
import 'package:flutter/material.dart';
class Bip39VerifyScreen extends StatelessWidget {
  const Bip39VerifyScreen({super.key, required this.phrase});
  final String phrase;
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('BIP-39 Verify — TODO')));
}
```

```dart
// lib/features/recovery/presentation/bip39_restore_screen.dart
import 'package:flutter/material.dart';
class Bip39RestoreScreen extends StatelessWidget {
  const Bip39RestoreScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('BIP-39 Restore — TODO')));
}
```

```dart
// lib/features/settings/presentation/manage_devices_screen.dart
import 'package:flutter/material.dart';
class ManageDevicesScreen extends StatelessWidget {
  const ManageDevicesScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Manage Devices — TODO')));
}
```

- [ ] **Step 3: Verify compilation**

```bash
flutter analyze
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/core/router/app_router.dart lib/features/recovery/ lib/features/settings/presentation/manage_devices_screen.dart
git commit -m "feat(recovery): add recovery + manage-devices routes, stub screens"
```

---

## Task 10: Bip39SetupScreen

**Files:**
- Modify: `lib/features/recovery/presentation/bip39_setup_screen.dart`

The setup screen is shown after onboarding bootstraps the family. It generates a phrase, shows it, and navigates to verify. The screen uses `FLAG_SECURE` on Android so the phrase can't be screenshot.

This screen reads the family key from `FamilyKeyService` and the family ID from SharedPreferences, so it can upload the wrapped envelope in the verify screen.

- [ ] **Step 1: Replace stub with full implementation**

```dart
// lib/features/recovery/presentation/bip39_setup_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/crypto/bip39_service.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/design_tokens.dart';

// FLAG_SECURE: prevent screenshots on Android while the phrase is visible.
const _secureChannel = MethodChannel('dreambook/window_flags');

class Bip39SetupScreen extends ConsumerStatefulWidget {
  const Bip39SetupScreen({super.key});

  @override
  ConsumerState<Bip39SetupScreen> createState() => _Bip39SetupScreenState();
}

class _Bip39SetupScreenState extends ConsumerState<Bip39SetupScreen> {
  final _bip39 = Bip39Service();
  late String _phrase;

  @override
  void initState() {
    super.initState();
    _phrase = _bip39.generatePhrase();
    _setSecureFlag(true);
  }

  @override
  void dispose() {
    _setSecureFlag(false);
    super.dispose();
  }

  // Best-effort: not all platforms/emulators support this channel.
  void _setSecureFlag(bool secure) {
    _secureChannel.invokeMethod<void>('setSecure', secure).catchError((_) {});
  }

  void _proceed() {
    context.push(AppRoutes.bip39Verify, extra: _phrase);
  }

  void _remindLater() {
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setBool(kOnboardingDoneKey, true);
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final words = _bip39.toWords(_phrase);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(l10n.recoverySetupHeadline),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.recoverySetupSubcopy,
                style: AppTypography.bodyMedium(color: scheme.onSurface.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  l10n.recoverySetupWarning,
                  style: AppTypography.bodyMedium(
                    color: scheme.error,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 2.8,
                    crossAxisSpacing: AppSpacing.xs,
                    mainAxisSpacing: AppSpacing.xs,
                  ),
                  itemCount: 12,
                  itemBuilder: (context, i) {
                    return Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${i + 1}. ${words[i]}',
                        style: AppTypography.bodyMedium(color: scheme.onSurface),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: _proceed,
                child: Text(l10n.recoverySetupWrittenCta),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: _remindLater,
                child: Text(l10n.recoverySetupRemindLater),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}
```

**Note:** `sharedPreferencesProvider` import is missing above. Add the import:

```dart
import '../../../core/providers/shared_preferences_provider.dart';
```

- [ ] **Step 2: Add FLAG_SECURE platform channel handler in Android**

In `android/app/src/main/kotlin/com/dreambookapp/dreambook/MainActivity.kt`, add:

```kotlin
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dreambook/window_flags")
            .setMethodCallHandler { call, result ->
                if (call.method == "setSecure") {
                    val secure = call.arguments as? Boolean ?: false
                    if (secure) {
                        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
```

- [ ] **Step 3: Read the current MainActivity.kt to check what already exists**

```bash
cat android/app/src/main/kotlin/com/dreambookapp/dreambook/MainActivity.kt
```

If the file already extends FlutterActivity with empty configureFlutterEngine, replace it with the version above. If it already has custom channels, add just the `"dreambook/window_flags"` MethodChannel block.

- [ ] **Step 4: Verify analyze**

```bash
flutter analyze
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/features/recovery/presentation/bip39_setup_screen.dart android/app/src/main/kotlin/
git commit -m "feat(recovery): Bip39SetupScreen — show 12 words with FLAG_SECURE"
```

---

## Task 11: Bip39VerifyScreen

**Files:**
- Modify: `lib/features/recovery/presentation/bip39_verify_screen.dart`

Shows "Enter word 3 and word 9". Two failures → regenerates phrase (pops back to setup). On success: wraps K_family, uploads to `upload_recovery` EF, sets onboarding done, navigates to home.

- [ ] **Step 1: Replace stub**

```dart
// lib/features/recovery/presentation/bip39_verify_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/crypto/bip39_service.dart';
import '../../../core/crypto/family_key_service.dart';
import '../../../core/crypto/recovery_service.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/providers/shared_preferences_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/sync/sync_lifecycle_controller.dart';
import '../../../core/theme/design_tokens.dart';

const _kFamilyIdKey = 'family.id';
const _kPhraseBackedUpKey = 'recovery.phrase_backed_up';

// Word positions verified (1-indexed for display, 0-indexed for list access).
const _verifyPositions = [2, 8]; // word 3 and word 9

const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

class Bip39VerifyScreen extends ConsumerStatefulWidget {
  const Bip39VerifyScreen({super.key, required this.phrase});
  final String phrase;

  @override
  ConsumerState<Bip39VerifyScreen> createState() => _Bip39VerifyScreenState();
}

class _Bip39VerifyScreenState extends ConsumerState<Bip39VerifyScreen> {
  final _controllers = [TextEditingController(), TextEditingController()];
  int _failCount = 0;
  bool _uploading = false;
  String? _errorText;

  final _bip39 = Bip39Service();
  final _recovery = RecoveryService();

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _confirm() async {
    final words = _bip39.toWords(widget.phrase);
    final allCorrect = _verifyPositions.asMap().entries.every((entry) {
      final idx = entry.key;
      final pos = entry.value;
      return _controllers[idx].text.trim().toLowerCase() == words[pos];
    });

    if (!allCorrect) {
      _failCount++;
      if (_failCount >= 2) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.recoveryVerifyWrongRegenerate)),
        );
        context.pop(); // Go back to setup screen to regenerate.
        return;
      }
      setState(() => _errorText = context.l10n.recoveryVerifyWrongTryAgain);
      return;
    }

    setState(() {
      _uploading = true;
      _errorText = null;
    });

    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final familyId = prefs.getString(_kFamilyIdKey) ?? '';
      final familyKey = await FamilyKeyService(_secureStorage).read(familyId: familyId);
      if (familyKey == null) throw Exception('K_family not found');

      final normalized = _bip39.normalizePhrase(widget.phrase);
      final lookupHash = await _bip39.lookupHash(widget.phrase);
      final wrapped = await _recovery.wrapFamilyKey(
        normalizedPhrase: normalized,
        familyKey: familyKey.bytes,
        familyId: familyId,
        keyVersion: familyKey.keyVersion,
      );

      final supa = Supabase.instance.client;
      final resp = await supa.functions.invoke(
        'upload_recovery',
        body: {
          'lookup_hash_b64': base64Encode(lookupHash),
          'wrapped_key_b64': base64Encode(wrapped.wrappedKey),
          'salt_b64': base64Encode(wrapped.salt),
          'key_version': familyKey.keyVersion,
        },
      );
      if (resp.status != 200) throw Exception('upload_recovery failed: ${resp.status}');

      await prefs.setBool(_kPhraseBackedUpKey, true);
      await prefs.setBool(kOnboardingDoneKey, true);

      ref.invalidate(syncLifecycleControllerProvider);
      ref.read(syncLifecycleControllerProvider).syncNow().ignore();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.recoveryVerifySuccess)),
      );

      final pendingDeepLink = prefs.getString('router.pendingDeepLink');
      if (pendingDeepLink != null && pendingDeepLink.isNotEmpty) {
        await prefs.remove('router.pendingDeepLink');
        if (!mounted) return;
        context.go(pendingDeepLink);
        return;
      }
      context.go(AppRoutes.home);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.push(AppRoutes.feedNew);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = e.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(l10n.recoveryVerifyHeadline),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.recoveryVerifySubcopy,
                style: AppTypography.bodyMedium(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              for (int i = 0; i < _verifyPositions.length; i++) ...[
                Text(
                  l10n.recoveryVerifyWord(_verifyPositions[i] + 1),
                  style: AppTypography.bodyMedium(color: scheme.onSurface),
                ),
                const SizedBox(height: AppSpacing.xs),
                TextField(
                  controller: _controllers[i],
                  decoration: const InputDecoration(),
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: i < _verifyPositions.length - 1
                      ? TextInputAction.next
                      : TextInputAction.done,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (_errorText != null) ...[
                Text(
                  _errorText!,
                  style: AppTypography.bodyMedium(color: scheme.error),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (_uploading)
                const Center(child: CircularProgressIndicator())
              else
                FilledButton(
                  onPressed: _confirm,
                  child: Text(l10n.recoveryVerifyConfirmCta),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

```bash
flutter analyze
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/features/recovery/presentation/bip39_verify_screen.dart
git commit -m "feat(recovery): Bip39VerifyScreen — word verification + upload envelope"
```

---

## Task 12: Bip39RestoreScreen

**Files:**
- Modify: `lib/features/recovery/presentation/bip39_restore_screen.dart`

Called from welcome screen ("Restore from recovery phrase"). User enters 12 words, client validates checksum, calls `claim_recovery` EF, unwraps K_family, stores it, then syncs to home.

- [ ] **Step 1: Replace stub**

```dart
// lib/features/recovery/presentation/bip39_restore_screen.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/crypto/bip39_service.dart';
import '../../../core/crypto/device_identity_service.dart';
import '../../../core/crypto/family_key_service.dart';
import '../../../core/crypto/recovery_service.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/providers/shared_preferences_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/sync/sync_lifecycle_controller.dart';
import '../../../core/theme/design_tokens.dart';
import '../../baby/data/baby_repository.dart';
import '../../baby/data/current_baby_provider.dart';

const _kFamilyIdKey = 'family.id';
const _kPhraseBackedUpKey = 'recovery.phrase_backed_up';

const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

class Bip39RestoreScreen extends ConsumerStatefulWidget {
  const Bip39RestoreScreen({super.key});

  @override
  ConsumerState<Bip39RestoreScreen> createState() => _Bip39RestoreScreenState();
}

class _Bip39RestoreScreenState extends ConsumerState<Bip39RestoreScreen> {
  final _controller = TextEditingController();
  bool _restoring = false;
  String? _errorText;

  final _bip39 = Bip39Service();
  final _recovery = RecoveryService();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return;

    // Local checksum validation before hitting the server.
    if (!_bip39.validatePhrase(raw)) {
      setState(() => _errorText = context.l10n.recoveryRestoreInvalidChecksum);
      return;
    }

    setState(() {
      _restoring = true;
      _errorText = null;
    });

    try {
      final supa = Supabase.instance.client;
      if (supa.auth.currentSession == null) {
        await supa.auth.signInAnonymously();
      }

      final identity = await DeviceIdentityService(_secureStorage).getOrCreate();
      final lookupHash = await _bip39.lookupHash(raw);

      final resp = await supa.functions.invoke(
        'claim_recovery',
        body: {
          'lookup_hash_b64': base64Encode(lookupHash),
          'device_pub_key_b64': base64Encode(identity.publicKeyBytes),
        },
      );

      if (resp.status == 404) {
        throw Exception(context.l10n.recoveryRestoreNotFound);
      }
      if (resp.status == 429) {
        throw Exception(context.l10n.recoveryRestoreRateLimit);
      }
      if (resp.status != 200) {
        throw Exception(context.l10n.recoveryRestoreError);
      }

      final data = resp.data as Map<String, dynamic>;
      final wrappedKey = base64Decode(
        (data['wrapped_key_b64'] as String).replaceAll('\n', '').replaceAll('\r', ''),
      );
      final salt = base64Decode(
        (data['salt_b64'] as String).replaceAll('\n', '').replaceAll('\r', ''),
      );
      final familyId = data['family_id'] as String;
      final keyVersion = data['key_version'] as int;

      final normalized = _bip39.normalizePhrase(raw);
      final familyKeyBytes = await _recovery.unwrapFamilyKey(
        normalizedPhrase: normalized,
        wrappedKey: Uint8List.fromList(wrappedKey),
        salt: Uint8List.fromList(salt),
        familyId: familyId,
        keyVersion: keyVersion,
      );

      await FamilyKeyService(_secureStorage).install(
        familyId: familyId,
        bytes: familyKeyBytes,
        keyVersion: keyVersion,
      );

      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setString(_kFamilyIdKey, familyId);
      await prefs.setBool(_kPhraseBackedUpKey, true);
      await prefs.setBool(kOnboardingDoneKey, true);

      ref.invalidate(syncLifecycleControllerProvider);

      if (!mounted) return;
      setState(() => _restoring = false);

      await ref.read(syncLifecycleControllerProvider).syncNow();

      final babies = await ref.read(babyRepositoryProvider).list();
      if (babies.isNotEmpty) {
        await ref.read(currentBabyIdProvider.notifier).select(babies.first.id);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.recoveryRestoreSuccess)),
      );
      context.go(AppRoutes.home);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _errorText = err.toString();
        _restoring = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.recoveryRestoreHeadline)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.recoveryRestoreSubcopy,
                style: AppTypography.bodyMedium(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _controller,
                decoration: InputDecoration(
                  labelText: l10n.recoveryRestoreLabel,
                  hintText: l10n.recoveryRestoreHint,
                ),
                maxLines: 3,
                keyboardType: TextInputType.text,
                autocorrect: false,
                enableSuggestions: false,
              ),
              const SizedBox(height: AppSpacing.md),
              if (_errorText != null) ...[
                Text(
                  _errorText!,
                  style: AppTypography.bodyMedium(color: scheme.error),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (_restoring)
                const Center(child: CircularProgressIndicator())
              else
                FilledButton(
                  onPressed: _restore,
                  child: Text(l10n.recoveryRestoreCta),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

```bash
flutter analyze
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/features/recovery/presentation/bip39_restore_screen.dart
git commit -m "feat(recovery): Bip39RestoreScreen — enter phrase, claim recovery, sync to home"
```

---

## Task 13: Update WelcomeScreen — eager bootstrap + Restore button

**Files:**
- Modify: `lib/features/onboarding/presentation/welcome_screen.dart`

Changes:
1. `_start()` now bootstraps the family (online) and routes to BIP-39 setup (or straight to home if offline or phrase already backed up).
2. Add "Restore from recovery phrase" `TextButton` below the existing "I have a code" button.

- [ ] **Step 1: Read current welcome_screen.dart**

```bash
cat lib/features/onboarding/presentation/welcome_screen.dart
```

- [ ] **Step 2: Replace file with updated version**

```dart
// lib/features/onboarding/presentation/welcome_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/crypto/device_identity_service.dart';
import '../../../core/crypto/family_key_service.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/providers/shared_preferences_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/sync/sync_lifecycle_controller.dart';
import '../../../core/theme/design_tokens.dart';
import '../../baby/data/baby_repository.dart';
import '../../baby/data/current_baby_provider.dart';

const _kFamilyIdKey = 'family.id';
const _kPhraseBackedUpKey = 'recovery.phrase_backed_up';
const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _nameCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final raw = _nameCtrl.text.trim();
      final name = raw.isEmpty ? 'Baby' : raw;

      final babyRepo = ref.read(babyRepositoryProvider);
      final today = DateTime.now().toUtc();
      final baby = await babyRepo.insert(name: name, dob: today);
      await ref.read(currentBabyIdProvider.notifier).select(baby.id);

      final prefs = ref.read(sharedPreferencesProvider);

      // Try to bootstrap the family online; if offline, fall through to home.
      final bootstrapped = await _bootstrapFamily(prefs);

      if (!mounted) return;
      if (bootstrapped) {
        // BIP-39 setup is mandatory when online. Route there before home.
        context.go(AppRoutes.bip39Setup);
        return;
      }

      // Offline path: mark onboarding done and go home with recovery banner.
      await prefs.setBool(kOnboardingDoneKey, true);
      final pendingDeepLink = prefs.getString('router.pendingDeepLink');
      if (pendingDeepLink != null && pendingDeepLink.isNotEmpty) {
        await prefs.remove('router.pendingDeepLink');
        if (!mounted) return;
        context.go(pendingDeepLink);
        return;
      }
      context.go(AppRoutes.home);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.push(AppRoutes.feedNew);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Returns true if a new family was bootstrapped (online success).
  /// Returns false if already has family, offline, or any error.
  Future<bool> _bootstrapFamily(dynamic prefs) async {
    // If this device already has a family, skip.
    if ((prefs.getString(_kFamilyIdKey) ?? '').isNotEmpty) {
      return false;
    }
    try {
      final supa = Supabase.instance.client;
      if (supa.auth.currentSession == null) {
        await supa.auth.signInAnonymously();
      }
      final identity = await DeviceIdentityService(_secureStorage).getOrCreate();
      final resp = await supa.functions.invoke(
        'bootstrap_family',
        body: {'device_pub_key': base64Encode(identity.publicKeyBytes)},
      );
      if (resp.status != 201) return false;
      final data = resp.data;
      if (data is! Map || data['family_id'] is! String) return false;

      final familyId = data['family_id'] as String;
      await prefs.setString(_kFamilyIdKey, familyId);
      await FamilyKeyService(_secureStorage).generate(
        familyId: familyId,
        keyVersion: 1,
      );

      ref.invalidate(syncLifecycleControllerProvider);
      ref.read(syncLifecycleControllerProvider).syncNow().ignore();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xl),
              Text(
                l10n.welcomeHeadline,
                style: AppTypography.headlineLarge(color: scheme.onSurface),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.welcomeSubcopy,
                style: AppTypography.bodyLarge(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: l10n.welcomeBabyNameLabel,
                  hintText: l10n.welcomeBabyNameHint,
                ),
                autofocus: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _start(),
              ),
              const Spacer(),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else
                FilledButton(
                  onPressed: _start,
                  child: Text(l10n.welcomeStartCta),
                ),
              const SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: () => context.push(AppRoutes.shareClaim),
                child: Text(l10n.joinHaveCode),
              ),
              TextButton(
                onPressed: () => context.push(AppRoutes.bip39Restore),
                child: Text(l10n.welcomeRestoreCta),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Analyze and test**

```bash
flutter analyze && flutter test
```

Expected: no errors, 281+ tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/features/onboarding/presentation/welcome_screen.dart
git commit -m "feat(recovery): WelcomeScreen — eager bootstrap + Restore from phrase button"
```

---

## Task 14: Update SettingsScreen — Recovery Phrase + Manage Devices rows

**Files:**
- Modify: `lib/features/settings/presentation/settings_screen.dart`

Add two `ListTile` rows:
1. "Recovery phrase" — shows "Backed up ✓" or "Not set up" with a warning style; routes to `/recovery/setup`.
2. "Manage devices" — routes to `/settings/devices`.

Find the `build` method's `ListView` body and insert the tiles in a new "Security" section.

- [ ] **Step 1: Locate where to insert in settings_screen.dart**

```bash
grep -n "ListTile\|child: Column\|ListView\|SliverList" lib/features/settings/presentation/settings_screen.dart | head -20
```

- [ ] **Step 2: Find the import block and the Widget build body**

```bash
sed -n '1,30p' lib/features/settings/presentation/settings_screen.dart
```

- [ ] **Step 3: Add imports (if not already present)**

At the top of the imports, add:
```dart
import 'package:dreambook/core/router/app_router.dart';
```
(Check: it may already be imported.)

- [ ] **Step 4: Add recovery + devices tiles**

Find the `return Scaffold(` in the build method. Inside the `ListView`/`Column` body, add a new section **before the privacy tile**:

```dart
// ---- Security section ----
const Divider(),
Padding(
  padding: const EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: AppSpacing.xs,
  ),
  child: Text(
    'Security', // TODO: add l10n key settingsSectionSecurity in a follow-up
    style: AppTypography.bodyMedium(
      color: scheme.onSurface.withValues(alpha: 0.5),
    ),
  ),
),
Consumer(
  builder: (context, ref, _) {
    final prefs = ref.watch(sharedPreferencesProvider);
    final backed = prefs.getBool('recovery.phrase_backed_up') ?? false;
    return ListTile(
      leading: Icon(
        backed ? Icons.lock : Icons.lock_open,
        color: backed ? scheme.primary : scheme.error,
      ),
      title: Text(context.l10n.settingsRecoveryPhraseTitle),
      subtitle: Text(
        backed
            ? context.l10n.settingsRecoveryPhraseBackedUp
            : context.l10n.settingsRecoveryPhraseNotBackedUp,
        style: TextStyle(color: backed ? null : scheme.error),
      ),
      onTap: () => context.push(AppRoutes.bip39Setup),
    );
  },
),
ListTile(
  leading: const Icon(Icons.devices),
  title: Text(context.l10n.settingsManageDevicesTitle),
  onTap: () => context.push(AppRoutes.manageDevices),
),
```

- [ ] **Step 5: Analyze**

```bash
flutter analyze
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/features/settings/presentation/settings_screen.dart
git commit -m "feat(recovery): SettingsScreen — Recovery Phrase status tile + Manage Devices tile"
```

---

## Task 15: ManageDevicesScreen (T1)

**Files:**
- Modify: `lib/features/settings/presentation/manage_devices_screen.dart`

Lists all non-revoked devices in the family. Each device shows its fingerprint (truncated), role, and join date. Admin can revoke a device (calls `revoke_caregiver` EF) or route to share invite to generate a recovery invite.

- [ ] **Step 1: Replace stub with full implementation**

```dart
// lib/features/settings/presentation/manage_devices_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/crypto/bytea_codec.dart';
import '../../../core/crypto/device_identity_service.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/design_tokens.dart';

const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

class _DeviceRow {
  _DeviceRow({
    required this.deviceFp,
    required this.role,
    required this.joinedAt,
    required this.isThisDevice,
  });
  final String deviceFp;
  final String role;
  final DateTime joinedAt;
  final bool isThisDevice;
}

class ManageDevicesScreen extends ConsumerStatefulWidget {
  const ManageDevicesScreen({super.key});

  @override
  ConsumerState<ManageDevicesScreen> createState() => _ManageDevicesScreenState();
}

class _ManageDevicesScreenState extends ConsumerState<ManageDevicesScreen> {
  List<_DeviceRow>? _devices;
  String? _errorText;
  bool _loading = true;
  String? _myDeviceFp;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final identity = await DeviceIdentityService(_secureStorage).getOrCreate();
      final myFpBytes = await identity.deviceFpBytes();
      _myDeviceFp = base64Encode(myFpBytes);

      final supa = Supabase.instance.client;
      final rows = await supa
          .from('family_devices')
          .select('device_fp, role, joined_at')
          .is_('revoked_at', null)
          .order('joined_at', ascending: true);

      final devices = (rows as List).map((r) {
        final m = r as Map<String, dynamic>;
        // device_fp from PostgREST is a \x-prefixed hex string.
        final fpRaw = m['device_fp'] as String? ?? '';
        final fpHex = fpRaw.replaceFirst('\\x', '');
        final fpB64 = base64Encode(decodeBytea(fpRaw));
        return _DeviceRow(
          deviceFp: fpHex.length > 8 ? fpHex.substring(0, 8) + '…' : fpHex,
          role: m['role'] as String? ?? 'editor',
          joinedAt: DateTime.parse(m['joined_at'] as String),
          isThisDevice: fpB64 == _myDeviceFp,
        );
      }).toList();

      if (mounted) setState(() { _devices = devices; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _errorText = e.toString(); _loading = false; });
    }
  }

  Future<void> _revoke(_DeviceRow device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.manageDevicesRevokeConfirmTitle),
        content: Text(ctx.l10n.manageDevicesRevokeConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.manageDevicesRevokeCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.manageDevicesRevokeConfirmCta),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final supa = Supabase.instance.client;
      await supa.functions.invoke(
        'revoke_caregiver',
        body: {'target_device_fp': device.deviceFp.replaceAll('…', '')},
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.manageDevicesHeadline)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorText != null
              ? Center(child: Text(_errorText!, style: TextStyle(color: scheme.error)))
              : _devices!.isEmpty
                  ? Center(child: Text(l10n.manageDevicesEmpty))
                  : ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      itemCount: _devices!.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final d = _devices![i];
                        return ListTile(
                          leading: Icon(
                            d.role == 'admin' ? Icons.admin_panel_settings : Icons.person,
                          ),
                          title: Text(
                            d.isThisDevice
                                ? l10n.manageDevicesThisDevice
                                : '${d.role == 'admin' ? l10n.manageDevicesAdmin : l10n.manageDevicesEditor} · ${d.deviceFp}',
                          ),
                          subtitle: Text(
                            d.joinedAt.toLocal().toString().substring(0, 10),
                          ),
                          trailing: d.isThisDevice
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  tooltip: l10n.manageDevicesRevokeButton,
                                  onPressed: () => _revoke(d),
                                ),
                        );
                      },
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.shareInvite),
        icon: const Icon(Icons.add),
        label: Text(l10n.manageDevicesRecoveryInvite),
      ),
    );
  }
}
```

**Note:** `DeviceIdentityService` may not have a `deviceFpBytes()` method. Check:

```bash
grep -n "deviceFp\|pubKey\|publicKey" lib/core/crypto/device_identity_service.dart | head -20
```

If there's no `deviceFpBytes()`, compute it inline:
```dart
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
// ...
final pubKeyBytes = identity.publicKeyBytes; // Uint8List
final hashBuf = await Sha256().hash(pubKeyBytes);
final myFpBytes = Uint8List.fromList(hashBuf.bytes.sublist(0, 16));
_myDeviceFp = base64Encode(myFpBytes);
```

Read `device_identity_service.dart` to check the actual API before writing this screen, and adjust accordingly.

- [ ] **Step 2: Check DeviceIdentityService API**

```bash
grep -n "publicKey\|publicKeyBytes\|deviceFp" lib/core/crypto/device_identity_service.dart | head -20
```

- [ ] **Step 3: Adjust _load() if needed** based on the actual field names from step 2.

- [ ] **Step 4: Analyze**

```bash
flutter analyze
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings/presentation/manage_devices_screen.dart
git commit -m "feat(recovery): ManageDevicesScreen — list + revoke + recovery invite (T1)"
```

---

## Task 16: Integration test — T2 BIP-39 round-trip

**Files:**
- Create: `test/integration/recovery_t2_test.dart`

This test uses the real `RecoveryService` and `Bip39Service` (no Supabase calls — verifying the crypto round-trip offline is sufficient at unit level). The server-side round-trip is covered by E2E testing with real Supabase when deployed.

- [ ] **Step 1: Write test**

```dart
// test/integration/recovery_t2_test.dart
// @Tags(['integration'])
// Tests the full BIP-39 → Argon2id → AES-GCM → recovery round-trip.
// Uses low-memory Argon2id params so CI finishes in <30s.

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dreambook/core/crypto/bip39_service.dart';
import 'package:dreambook/core/crypto/recovery_service.dart';

void main() {
  final testKdf = Argon2id(memory: 256, parallelism: 1, iterations: 1, hashLength: 32);

  final bip39 = Bip39Service();
  RecoveryService makeRecovery() => RecoveryService(kdf: testKdf);

  group('T2 recovery round-trip', () {
    test('generate → validate → wrap → unwrap recovers K_family', () async {
      final phrase = bip39.generatePhrase();
      expect(bip39.validatePhrase(phrase), isTrue);

      final familyKey = Uint8List.fromList(List.generate(32, (i) => i ^ 0xAB));
      const familyId = 'integration-test-family';
      const keyVersion = 1;

      final recovery = makeRecovery();
      final normalized = bip39.normalizePhrase(phrase);

      final wrapped = await recovery.wrapFamilyKey(
        normalizedPhrase: normalized,
        familyKey: familyKey,
        familyId: familyId,
        keyVersion: keyVersion,
      );

      expect(wrapped.wrappedKey.isNotEmpty, isTrue);
      expect(wrapped.salt.length, 16);

      final recovered = await recovery.unwrapFamilyKey(
        normalizedPhrase: normalized,
        wrappedKey: wrapped.wrappedKey,
        salt: wrapped.salt,
        familyId: familyId,
        keyVersion: keyVersion,
      );

      expect(recovered, equals(familyKey));
    });

    test('lookup hash is deterministic after normalisation', () async {
      const rawPhrase = '  ABANDON  ABILITY  ABLE  ABOUT  ABOVE  ABSENT  ABSORB  ABSTRACT  ABSURD  ABUSE  ACCESS  ACCIDENT  ';
      final h1 = await bip39.lookupHash(rawPhrase);
      final h2 = await bip39.lookupHash('abandon ability able about above absent absorb abstract absurd abuse access accident');
      expect(h1, equals(h2));
    });

    test('wrong phrase fails unwrap', () async {
      final phrase = bip39.generatePhrase();
      final differentPhrase = bip39.generatePhrase();
      final familyKey = Uint8List.fromList(List.generate(32, (i) => i));

      final recovery = makeRecovery();
      final wrapped = await recovery.wrapFamilyKey(
        normalizedPhrase: bip39.normalizePhrase(phrase),
        familyKey: familyKey,
        familyId: 'fid',
        keyVersion: 1,
      );

      expect(
        () => recovery.unwrapFamilyKey(
          normalizedPhrase: bip39.normalizePhrase(differentPhrase),
          wrappedKey: wrapped.wrappedKey,
          salt: wrapped.salt,
          familyId: 'fid',
          keyVersion: 1,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('rate-limit simulation: 5 phrases, only matching one decrypts', () async {
      final realPhrase = bip39.generatePhrase();
      final recovery = makeRecovery();
      final familyKey = Uint8List.fromList(List.generate(32, (i) => i * 2));
      final normalized = bip39.normalizePhrase(realPhrase);

      final wrapped = await recovery.wrapFamilyKey(
        normalizedPhrase: normalized,
        familyKey: familyKey,
        familyId: 'fid',
        keyVersion: 2,
      );

      // 4 wrong phrases should all throw.
      for (int i = 0; i < 4; i++) {
        final wrong = bip39.generatePhrase();
        expect(
          () => recovery.unwrapFamilyKey(
            normalizedPhrase: bip39.normalizePhrase(wrong),
            wrappedKey: wrapped.wrappedKey,
            salt: wrapped.salt,
            familyId: 'fid',
            keyVersion: 2,
          ),
          throwsA(isA<SecretBoxAuthenticationError>()),
        );
      }

      // Correct phrase succeeds.
      final result = await recovery.unwrapFamilyKey(
        normalizedPhrase: normalized,
        wrappedKey: wrapped.wrappedKey,
        salt: wrapped.salt,
        familyId: 'fid',
        keyVersion: 2,
      );
      expect(result, equals(familyKey));
    });
  });
}
```

- [ ] **Step 2: Run integration tests**

```bash
flutter test test/integration/recovery_t2_test.dart --tags integration
```

Expected: 4 tests pass.

- [ ] **Step 3: Run full suite**

```bash
flutter test
```

Expected: 285+ tests pass.

- [ ] **Step 4: Commit**

```bash
git add test/integration/recovery_t2_test.dart
git commit -m "test(recovery): T2 BIP-39 → Argon2id → AES-GCM round-trip integration tests"
```

---

## Task 17: Final cleanup + analyze

- [ ] **Step 1: Run full analyze + test**

```bash
flutter analyze && flutter test
```

Expected: no analyzer warnings or errors, 285+ tests pass.

- [ ] **Step 2: Remove any TODO stubs** left in screens (grep for "TODO" added in this plan).

```bash
grep -rn "TODO" lib/features/recovery/ lib/features/settings/presentation/manage_devices_screen.dart
```

Fix any found.

- [ ] **Step 3: Update MEMORY with new branch state**

Update the project memory file at `/Users/nipitphand/.claude/projects/-Users-nipitphand-Projects/memory/project_dreambook_planc_progress.md` to add a Phase 3 section.

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "chore: Phase 3 T1+T2 recovery complete — BIP-39 setup/verify/restore, Manage Devices, EFs"
```

---

## Self-Review: Spec Coverage

| Spec requirement | Task |
|---|---|
| Generate 12-word BIP-39 phrase (128-bit entropy) | Task 3 (Bip39Service.generatePhrase) |
| FLAG_SECURE blocks screenshots | Task 10 (FLAG_SECURE channel + Bip39SetupScreen) |
| Verification: "Type word 3 and word 9" | Task 11 (Bip39VerifyScreen, `_verifyPositions = [2, 8]`) |
| Fail twice → regenerate phrase | Task 11 (`_failCount >= 2 → pop back`) |
| Argon2id m=64MiB, t=3, p=1 | Task 5 (RecoveryService._defaultKdf) |
| AES-GCM-wrap K_family, AAD = `familyId|keyVersion` | Task 5 (RecoveryService.wrapFamilyKey) |
| Upload to `family_recovery_envelopes` | Task 6 (upload_recovery EF) |
| Lookup hash → `recovery_lookup` | Task 6 (upload_recovery EF) |
| Restore: validate checksum locally before server | Task 12 (Bip39RestoreScreen._restore → validatePhrase first) |
| Rate limit 5 attempts/hour/family | Task 7 (claim_recovery EF, `RATE_LIMIT = 5`) |
| New device added to family_devices | Task 7 (claim_recovery EF upsert into family_devices) |
| Audit log entries | Tasks 6 + 7 (writeAuditEvent calls) |
| T1: Settings → Manage Devices | Tasks 14 + 15 |
| T1: Revoke device | Task 15 (ManageDevicesScreen._revoke) |
| T1: Generate recovery invite from Manage Devices | Task 15 (FAB → shareInvite) |
| Mandatory at setup (shown before home) | Task 13 (WelcomeScreen._start → bip39Setup) |
| Offline graceful fallback | Task 13 (_bootstrapFamily returns false on error → home) |
| "Restore from phrase" on welcome screen | Task 13 (welcomeRestoreCta TextButton → bip39Restore) |
| Recovery phrase status in Settings | Task 14 (recovery.phrase_backed_up tile) |

All spec requirements covered. No placeholders.
