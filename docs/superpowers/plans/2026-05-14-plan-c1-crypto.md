# DreamBook Plan C-1 (Crypto) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship offline crypto primitives, secure key storage, device identity, and the `m003` schema migration that unlocks Plan C-2 (sync) and Plan C-3 (invite). No network code in this sub-plan.

**Architecture:** Pure-Dart crypto layer under `lib/core/crypto/` with no Flutter framework deps so primitives can be unit-tested in isolation. AES-GCM-256, Argon2id, BLAKE2b, Ed25519 via the `cryptography_flutter` plugin (native on Android/iOS) with the pure-Dart `cryptography` package as a fallback. Append-only migration extends Plan B's `Migrations([...])` runner. Each service has a fake-storage variant for tests so no network or platform channel is touched in CI.

**Tech Stack:** Flutter 3.41+, Dart 3.10+, `cryptography_flutter` ^2.x, `cryptography` ^2.7+, existing `flutter_secure_storage` ^10, `sqflite_sqlcipher` ^3.4.

**Source spec:** `docs/superpowers/specs/2026-05-14-plan-c-sync-crypto-design.md` §3.1 (C-crypto deliverables) and §6 (mobile hardening items 2/10/11/12).

---

## File structure

**New files:**
- `lib/core/crypto/family_key_service.dart`
- `lib/core/crypto/crypto_envelope.dart`
- `lib/core/crypto/invite_code_service.dart`
- `lib/core/crypto/device_identity_service.dart`
- `lib/core/crypto/key_rotation_service.dart`
- `lib/core/crypto/secure_wipe.dart`
- `lib/core/crypto/crockford_base32.dart`
- `lib/core/db/migrations/m003_v3.dart`
- `tool/check_manifest_security.sh`
- `android/app/proguard-rules.pro`
- `docs/build-flags.md`
- `test/core/crypto/crypto_envelope_test.dart`
- `test/core/crypto/secure_wipe_test.dart`
- `test/core/crypto/family_key_service_test.dart`
- `test/core/crypto/device_identity_service_test.dart`
- `test/core/crypto/invite_code_service_test.dart`
- `test/core/crypto/crockford_base32_test.dart`
- `test/core/crypto/key_rotation_service_test.dart`
- `test/core/db/migration_m003_test.dart`
- `test/_fakes/in_memory_secure_storage.dart`

**Modified files:**
- `pubspec.yaml` (add 2 deps)
- `lib/core/db/database_provider.dart` (register `m003V3`)
- `lib/core/services/secure_key_service.dart` (override iOS accessibility)
- `android/app/build.gradle` (link proguard-rules.pro)

---

## Task summary

| # | Task | Files | Tests added |
|---|---|---|---|
| 1 | Branch + deps setup | pubspec.yaml | – |
| 2 | Crockford base32 codec | `crockford_base32.dart` | 4 |
| 3 | CryptoEnvelope (AES-GCM-256) | `crypto_envelope.dart` | 5 |
| 4 | secureWipe helper | `secure_wipe.dart` | 2 |
| 5 | In-memory secure storage fake | `_fakes/in_memory_secure_storage.dart` | 0 (fixture) |
| 6 | FamilyKeyService | `family_key_service.dart` | 4 |
| 7 | DeviceIdentityService (Ed25519) | `device_identity_service.dart` | 3 |
| 8 | InviteCodeService | `invite_code_service.dart` | 5 |
| 9 | Migration m003_v3 | `m003_v3.dart` + register | 3 |
| 10 | KeyRotationService (orchestrator) | `key_rotation_service.dart` | 3 |
| 11 | Build hardening (ProGuard, obfuscate doc, iOS accessibility) | `proguard-rules.pro`, `build.gradle`, `secure_key_service.dart`, `docs/build-flags.md` | – |
| 12 | Manifest security check + final verify + tag | `tool/check_manifest_security.sh` | – |

**Test target after C-1:** ≥ 30 new tests on top of Plan B's 90 (total ≥ 120).

---

## Task 1: Branch + dependency setup

**Files:**
- Branch: `feat/plan-c-1-crypto` from tag `plan-b-complete`
- Modify: `pubspec.yaml`

- [ ] **Step 1: Create branch from plan-b-complete tag**

```bash
git fetch --tags
git checkout -b feat/plan-c-1-crypto plan-b-complete
git status
```

Expected: clean working tree, branch `feat/plan-c-1-crypto` created from tag.

- [ ] **Step 2: Add crypto dependencies to pubspec.yaml**

Replace the `# Utilities` block in `pubspec.yaml` with:

```yaml
  # Utilities
  uuid: ^4.5.3
  path: ^1.9.0

  # Crypto (Plan C-1) — native AES-GCM / Argon2id / Ed25519 / BLAKE2b
  cryptography: ^2.7.0
  cryptography_flutter: ^2.3.2
```

- [ ] **Step 3: Fetch packages**

Run: `flutter pub get`
Expected: "Got dependencies!" with no error.

- [ ] **Step 4: Verify cryptography_flutter native init compiles**

Create temporary throwaway probe file `lib/_probe.dart` (delete before commit):

```dart
import 'package:cryptography_flutter/cryptography_flutter.dart';

void probe() {
  FlutterCryptography.enable();
}
```

Run: `dart analyze lib/_probe.dart`
Expected: no errors.
Then: `rm lib/_probe.dart`

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore(c1): add cryptography deps for Plan C crypto layer"
```

---

## Task 2: Crockford base32 codec

The standard base32 alphabet contains ambiguous characters (`0/O`, `1/I/L`). Crockford uses `0-9 A-Z` minus `I L O U` (32 chars). We need encode (bytes → string) and decode (string → bytes) with collapse rules on decode so users can type lowercase or substitute ambiguous chars.

**Files:**
- Create: `lib/core/crypto/crockford_base32.dart`
- Create: `test/core/crypto/crockford_base32_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/core/crypto/crockford_base32_test.dart`:

```dart
import 'dart:typed_data';

import 'package:dreambook/core/crypto/crockford_base32.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CrockfordBase32', () {
    test('encodes 5-byte input to 8-char string from official alphabet', () {
      final bytes = Uint8List.fromList([0x12, 0x34, 0x56, 0x78, 0x9A]);
      final s = CrockfordBase32.encode(bytes);
      expect(s.length, 8);
      expect(RegExp(r'^[0-9A-HJKMNP-TV-Z]+$').hasMatch(s), isTrue);
    });

    test('round-trip 10k random 5-byte payloads', () {
      for (var i = 0; i < 10000; i++) {
        final bytes = Uint8List.fromList(
          List<int>.generate(5, (_) => (i * 7 + 13) & 0xFF),
        );
        final s = CrockfordBase32.encode(bytes);
        final back = CrockfordBase32.decode(s);
        expect(back, bytes, reason: 'round-trip failed at iteration $i');
      }
    });

    test('decode collapses ambiguous chars (i/I/l/L → 1, o/O → 0)', () {
      // 'IL01' should decode same as '1101' after normalisation.
      final a = CrockfordBase32.decode('1101AAAA');
      final b = CrockfordBase32.decode('iLO1AAAA');
      expect(b, a);
    });

    test('decode rejects U (Crockford excludes it)', () {
      expect(
        () => CrockfordBase32.decode('UUUUUUUU'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/crypto/crockford_base32_test.dart`
Expected: FAIL (file `crockford_base32.dart` not found).

- [ ] **Step 3: Implement Crockford codec**

Create `lib/core/crypto/crockford_base32.dart`:

```dart
import 'dart:typed_data';

/// Crockford base32 codec.
///
/// Alphabet: 0-9 A-Z minus I, L, O, U (32 chars).
/// Decode collapses common typos: i/I/l/L → 1, o/O → 0, lowercase → uppercase.
/// U/u always reject — they are explicitly excluded from the alphabet.
class CrockfordBase32 {
  CrockfordBase32._();

  static const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// Encodes bytes to a string. Output length = ceil(bytes.length * 8 / 5).
  static String encode(List<int> bytes) {
    if (bytes.isEmpty) return '';
    final out = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final b in bytes) {
      buffer = (buffer << 8) | (b & 0xFF);
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        out.write(_alphabet[(buffer >> bits) & 0x1F]);
      }
    }
    if (bits > 0) {
      out.write(_alphabet[(buffer << (5 - bits)) & 0x1F]);
    }
    return out.toString();
  }

  /// Decodes a Crockford-encoded string. Applies collapse rules:
  /// lowercase → uppercase, I/L → 1, O → 0. U/u throw FormatException.
  static Uint8List decode(String input) {
    if (input.isEmpty) return Uint8List(0);
    var buffer = 0;
    var bits = 0;
    final out = <int>[];
    for (final raw in input.split('')) {
      var c = raw.toUpperCase();
      if (c == '-' || c == ' ') continue; // group separators allowed
      if (c == 'I' || c == 'L') c = '1';
      if (c == 'O') c = '0';
      if (c == 'U') {
        throw const FormatException('Crockford alphabet excludes U');
      }
      final value = _alphabet.indexOf(c);
      if (value < 0) {
        throw FormatException('Not a Crockford base32 character: $raw');
      }
      buffer = (buffer << 5) | value;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xFF);
      }
    }
    return Uint8List.fromList(out);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/crypto/crockford_base32_test.dart`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/crypto/crockford_base32.dart test/core/crypto/crockford_base32_test.dart
git commit -m "feat(c1): Crockford base32 codec with collapse rules"
```

---

## Task 3: CryptoEnvelope (AES-GCM-256)

**Files:**
- Create: `lib/core/crypto/crypto_envelope.dart`
- Create: `test/core/crypto/crypto_envelope_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/core/crypto/crypto_envelope_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dreambook/core/crypto/crypto_envelope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SecretKey key;
  late CryptoEnvelope envelope;

  setUp(() async {
    key = await AesGcm.with256bits().newSecretKey();
    envelope = CryptoEnvelope();
  });

  group('CryptoEnvelope', () {
    test('seal then open round-trips plaintext', () async {
      final plaintext = utf8.encode('feed at 14:25, 4oz, left breast');
      final aad = utf8.encode('feed|abc123|3|fam-001|1');
      final ct = await envelope.seal(plaintext, key, aad);
      final back = await envelope.open(ct, key, aad);
      expect(back, plaintext);
    });

    test('open rejects ciphertext with tampered AAD', () async {
      final plaintext = utf8.encode('hello');
      final aad = utf8.encode('feed|id|1|fam|1');
      final ct = await envelope.seal(plaintext, key, aad);
      final tamperedAad = utf8.encode('feed|id|2|fam|1'); // version bumped
      expect(
        () => envelope.open(ct, key, tamperedAad),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('open rejects ciphertext under a different key', () async {
      final plaintext = utf8.encode('hello');
      final aad = utf8.encode('feed|id|1|fam|1');
      final ct = await envelope.seal(plaintext, key, aad);
      final otherKey = await AesGcm.with256bits().newSecretKey();
      expect(
        () => envelope.open(ct, otherKey, aad),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('seal produces unique nonces across 10k seals (probabilistic)', () async {
      final plaintext = utf8.encode('x');
      final aad = utf8.encode('a');
      final seen = <String>{};
      for (var i = 0; i < 10000; i++) {
        final ct = await envelope.seal(plaintext, key, aad);
        final nonce = base64Encode(ct.sublist(0, 12));
        expect(seen.add(nonce), isTrue,
            reason: 'nonce collision at iteration $i');
      }
    });

    test('envelope layout: 12-byte nonce prefix + ciphertext + 16-byte mac', () async {
      final plaintext = Uint8List.fromList(List.filled(100, 0x42));
      final aad = utf8.encode('a');
      final ct = await envelope.seal(plaintext, key, aad);
      // 12 (nonce) + 100 (ct same length as plaintext for GCM) + 16 (mac) = 128
      expect(ct.length, 12 + 100 + 16);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/crypto/crypto_envelope_test.dart`
Expected: FAIL (`crypto_envelope.dart` not found).

- [ ] **Step 3: Implement CryptoEnvelope**

Create `lib/core/crypto/crypto_envelope.dart`:

```dart
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// AES-GCM-256 envelope: `nonce(12) || ciphertext(N) || mac(16)`.
///
/// Per spec §3.1 and §5.1, the AAD must be the canonical row identity
/// `"${table}|${record_id}|${version}|${family_id}|${key_version}"` so a
/// tampered metadata field invalidates the MAC and the row is rejected.
class CryptoEnvelope {
  CryptoEnvelope({AesGcm? algorithm})
      : _aes = algorithm ?? AesGcm.with256bits();

  final AesGcm _aes;

  /// Seals [plaintext] under [key] with [aad]. Returns the envelope bytes.
  Future<Uint8List> seal(
    List<int> plaintext,
    SecretKey key,
    List<int> aad,
  ) async {
    final box = await _aes.encrypt(
      plaintext,
      secretKey: key,
      aad: aad,
    );
    final out = Uint8List(box.nonce.length + box.cipherText.length + box.mac.bytes.length);
    out.setRange(0, box.nonce.length, box.nonce);
    out.setRange(box.nonce.length, box.nonce.length + box.cipherText.length, box.cipherText);
    out.setRange(box.nonce.length + box.cipherText.length, out.length, box.mac.bytes);
    return out;
  }

  /// Opens [envelope] under [key] with [aad]. Returns plaintext or throws
  /// [SecretBoxAuthenticationError] on any mismatch (wrong key, tampered AAD,
  /// modified ciphertext, modified MAC).
  Future<Uint8List> open(
    Uint8List envelope,
    SecretKey key,
    List<int> aad,
  ) async {
    const nonceLen = 12;
    const macLen = 16;
    if (envelope.length < nonceLen + macLen) {
      throw const FormatException('Envelope too short');
    }
    final nonce = envelope.sublist(0, nonceLen);
    final ct = envelope.sublist(nonceLen, envelope.length - macLen);
    final mac = envelope.sublist(envelope.length - macLen);
    final box = SecretBox(ct, nonce: nonce, mac: Mac(mac));
    final pt = await _aes.decrypt(box, secretKey: key, aad: aad);
    return Uint8List.fromList(pt);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/crypto/crypto_envelope_test.dart`
Expected: 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/crypto/crypto_envelope.dart test/core/crypto/crypto_envelope_test.dart
git commit -m "feat(c1): AES-GCM-256 CryptoEnvelope with AAD binding"
```

---

## Task 4: secureWipe helper

**Files:**
- Create: `lib/core/crypto/secure_wipe.dart`
- Create: `test/core/crypto/secure_wipe_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/core/crypto/secure_wipe_test.dart`:

```dart
import 'dart:typed_data';

import 'package:dreambook/core/crypto/secure_wipe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('secureWipe', () {
    test('zeroes all bytes of a Uint8List in place', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      secureWipe(bytes);
      expect(bytes, Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 0]));
    });

    test('is safe on empty Uint8List', () {
      final bytes = Uint8List(0);
      secureWipe(bytes);
      expect(bytes.length, 0);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/crypto/secure_wipe_test.dart`
Expected: FAIL (file not found).

- [ ] **Step 3: Implement secureWipe**

Create `lib/core/crypto/secure_wipe.dart`:

```dart
import 'dart:typed_data';

/// Overwrites every byte of [buffer] with zero.
///
/// IMPORTANT — defense in depth only. The Dart VM may have copied this
/// buffer during GC compaction; those copies cannot be reached from here.
/// Treat this as a best-effort hygiene helper, not a guarantee. Per spec
/// §6.2 ("Uint8List zero-fill as a guarantee — SKIP / theater").
void secureWipe(Uint8List buffer) {
  for (var i = 0; i < buffer.length; i++) {
    buffer[i] = 0;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/crypto/secure_wipe_test.dart`
Expected: 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/crypto/secure_wipe.dart test/core/crypto/secure_wipe_test.dart
git commit -m "feat(c1): secureWipe helper for in-place byte zeroization"
```

---

## Task 5: In-memory secure-storage fake

A tiny fake that satisfies the read/write/delete subset of `FlutterSecureStorage` used by Plan C crypto services. Tests inject this fake; production code uses the real `FlutterSecureStorage`.

**Files:**
- Create: `test/_fakes/in_memory_secure_storage.dart`

- [ ] **Step 1: Create fake (no test of its own — it's a fixture used by later tasks)**

Create `test/_fakes/in_memory_secure_storage.dart`:

```dart
/// Minimal fake of FlutterSecureStorage used by Plan C-1 service tests.
///
/// Satisfies: read, write, delete, deleteAll, containsKey. Does NOT
/// implement: readAll, ios/android options. Tests override real storage
/// with this fake via constructor injection on each service.
class InMemorySecureStorage {
  final Map<String, String> _store = {};
  bool simulateReadCorruption = false;

  Future<String?> read({required String key}) async {
    if (simulateReadCorruption) {
      throw const _FakeStorageCorruption();
    }
    return _store[key];
  }

  Future<void> write({required String key, required String value}) async {
    _store[key] = value;
  }

  Future<void> delete({required String key}) async {
    _store.remove(key);
  }

  Future<void> deleteAll() async {
    _store.clear();
  }

  Future<bool> containsKey({required String key}) async {
    return _store.containsKey(key);
  }

  /// Test-only inspection.
  Map<String, String> get snapshot => Map.unmodifiable(_store);
}

class _FakeStorageCorruption implements Exception {
  const _FakeStorageCorruption();
}
```

- [ ] **Step 2: Verify file analyzes**

Run: `flutter analyze test/_fakes/in_memory_secure_storage.dart`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add test/_fakes/in_memory_secure_storage.dart
git commit -m "test(c1): in-memory secure-storage fake for crypto service tests"
```

---

## Task 6: FamilyKeyService

Stores `K_family` (32 random bytes) under alias `dreambook_family_key_v1` with hardware-backed secure storage. Loads on demand only; never cached in `keepAlive` providers (per spec §6.1 item 12).

**Files:**
- Create: `lib/core/crypto/family_key_service.dart`
- Create: `test/core/crypto/family_key_service_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/core/crypto/family_key_service_test.dart`:

```dart
import 'dart:typed_data';

import 'package:dreambook/core/crypto/family_key_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_fakes/in_memory_secure_storage.dart';

void main() {
  late InMemorySecureStorage storage;
  late FamilyKeyService service;

  setUp(() {
    storage = InMemorySecureStorage();
    service = FamilyKeyService.forTest(storage);
  });

  group('FamilyKeyService', () {
    test('generate() creates and persists a 32-byte key', () async {
      final key = await service.generate(familyId: 'fam-1', keyVersion: 1);
      expect(key.length, 32);
      final stored = await service.read(familyId: 'fam-1');
      expect(stored, isNotNull);
      expect(stored!.bytes, key);
      expect(stored.keyVersion, 1);
    });

    test('read() returns null when no key stored', () async {
      final r = await service.read(familyId: 'never-stored');
      expect(r, isNull);
    });

    test('rotate() replaces key + bumps version', () async {
      final v1 = await service.generate(familyId: 'fam-1', keyVersion: 1);
      final v2 = await service.rotate(familyId: 'fam-1');
      expect(v2.bytes.length, 32);
      expect(v2.keyVersion, 2);
      expect(v2.bytes, isNot(equals(v1)));
      final back = await service.read(familyId: 'fam-1');
      expect(back!.keyVersion, 2);
    });

    test('clear() wipes the entry', () async {
      await service.generate(familyId: 'fam-1', keyVersion: 1);
      await service.clear(familyId: 'fam-1');
      expect(await service.read(familyId: 'fam-1'), isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/crypto/family_key_service_test.dart`
Expected: FAIL (`family_key_service.dart` not found).

- [ ] **Step 3: Implement FamilyKeyService**

Create `lib/core/crypto/family_key_service.dart`:

```dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A family key snapshot loaded from secure storage.
class FamilyKey {
  const FamilyKey({required this.bytes, required this.keyVersion});

  final Uint8List bytes;
  final int keyVersion;
}

/// Holds `K_family` per family. Production uses [FlutterSecureStorage];
/// tests inject a fake via [FamilyKeyService.forTest].
///
/// Storage shape: one entry per family at
///   `dreambook_family_key_v1::${familyId}` → base64Url(bytes) + '|' + keyVersion.
class FamilyKeyService {
  FamilyKeyService(this._storage);

  /// Test-only constructor that accepts any storage with the same
  /// read/write/delete surface (e.g. InMemorySecureStorage).
  FamilyKeyService.forTest(dynamic storage) : _storage = storage;

  static const String _aliasPrefix = 'dreambook_family_key_v1::';

  // Typed as dynamic to allow both FlutterSecureStorage and the test fake
  // without bringing the fake into production code paths.
  final dynamic _storage;

  String _alias(String familyId) => '$_aliasPrefix$familyId';

  /// Generates a fresh 32-byte key, persists it, returns the bytes.
  Future<Uint8List> generate({
    required String familyId,
    required int keyVersion,
  }) async {
    final rng = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => rng.nextInt(256)),
    );
    await _write(familyId: familyId, bytes: bytes, keyVersion: keyVersion);
    return bytes;
  }

  /// Returns the stored key or null. Returns null on read errors too —
  /// caller's responsibility to decide whether to wipe + re-handshake.
  Future<FamilyKey?> read({required String familyId}) async {
    try {
      final raw = await _storage.read(key: _alias(familyId)) as String?;
      if (raw == null) return null;
      final parts = raw.split('|');
      if (parts.length != 2) return null;
      final bytes = base64Url.decode(parts[0]);
      final ver = int.tryParse(parts[1]);
      if (ver == null) return null;
      return FamilyKey(bytes: Uint8List.fromList(bytes), keyVersion: ver);
    } catch (_) {
      return null;
    }
  }

  /// Generates a new key and stores it with `keyVersion = old + 1`.
  Future<FamilyKey> rotate({required String familyId}) async {
    final current = await read(familyId: familyId);
    final nextVersion = (current?.keyVersion ?? 0) + 1;
    final bytes = await generate(familyId: familyId, keyVersion: nextVersion);
    return FamilyKey(bytes: bytes, keyVersion: nextVersion);
  }

  /// Removes the entry. Called on revocation/wipe paths.
  Future<void> clear({required String familyId}) async {
    await _storage.delete(key: _alias(familyId));
  }

  Future<void> _write({
    required String familyId,
    required Uint8List bytes,
    required int keyVersion,
  }) async {
    final encoded = '${base64Url.encode(bytes)}|$keyVersion';
    await _storage.write(key: _alias(familyId), value: encoded);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/crypto/family_key_service_test.dart`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/crypto/family_key_service.dart test/core/crypto/family_key_service_test.dart
git commit -m "feat(c1): FamilyKeyService — K_family lifecycle (generate/read/rotate/clear)"
```

---

## Task 7: DeviceIdentityService (Ed25519)

**Files:**
- Create: `lib/core/crypto/device_identity_service.dart`
- Create: `test/core/crypto/device_identity_service_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/core/crypto/device_identity_service_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dreambook/core/crypto/device_identity_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_fakes/in_memory_secure_storage.dart';

void main() {
  late InMemorySecureStorage storage;
  late DeviceIdentityService service;

  setUp(() {
    storage = InMemorySecureStorage();
    service = DeviceIdentityService.forTest(storage);
  });

  group('DeviceIdentityService', () {
    test('getOrCreate() generates new keypair on first call and persists', () async {
      final id1 = await service.getOrCreate();
      expect(id1.publicKeyBytes.length, 32);
      final id2 = await service.getOrCreate();
      expect(id2.publicKeyBytes, id1.publicKeyBytes,
          reason: 'second call must return same persisted keypair');
    });

    test('signature is verifiable with the returned public key', () async {
      final id = await service.getOrCreate();
      final message = utf8.encode('hello world');
      final sig = await service.sign(message);
      final algo = Ed25519();
      final pubKey = SimplePublicKey(id.publicKeyBytes, type: KeyPairType.ed25519);
      final ok = await algo.verify(
        message,
        signature: Signature(sig, publicKey: pubKey),
      );
      expect(ok, isTrue);
    });

    test('public key round-trips through base64Url encoding', () async {
      final id = await service.getOrCreate();
      final encoded = base64Url.encode(id.publicKeyBytes);
      final decoded = base64Url.decode(encoded);
      expect(Uint8List.fromList(decoded), id.publicKeyBytes);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/crypto/device_identity_service_test.dart`
Expected: FAIL (file not found).

- [ ] **Step 3: Implement DeviceIdentityService**

Create `lib/core/crypto/device_identity_service.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Device-level identity. One Ed25519 keypair per install, persisted in
/// secure storage. The public key is the device fingerprint sent to
/// Supabase at handshake (per spec §6.4 / auditor #1 recommendation).
class DeviceIdentity {
  const DeviceIdentity({required this.publicKeyBytes});
  final Uint8List publicKeyBytes;
}

class DeviceIdentityService {
  DeviceIdentityService(this._storage);
  DeviceIdentityService.forTest(dynamic storage) : _storage = storage;

  static const String _privKeyAlias = 'dreambook_device_priv_v1';
  static const String _pubKeyAlias = 'dreambook_device_pub_v1';

  final dynamic _storage;
  final Ed25519 _algo = Ed25519();

  Future<DeviceIdentity> getOrCreate() async {
    final existingPub = await _storage.read(key: _pubKeyAlias) as String?;
    if (existingPub != null) {
      return DeviceIdentity(
        publicKeyBytes: Uint8List.fromList(base64Url.decode(existingPub)),
      );
    }
    final pair = await _algo.newKeyPair();
    final pub = await pair.extractPublicKey();
    final priv = await pair.extractPrivateKeyBytes();
    await _storage.write(
      key: _privKeyAlias,
      value: base64Url.encode(priv),
    );
    await _storage.write(
      key: _pubKeyAlias,
      value: base64Url.encode(pub.bytes),
    );
    return DeviceIdentity(publicKeyBytes: Uint8List.fromList(pub.bytes));
  }

  Future<List<int>> sign(List<int> message) async {
    final privRaw = await _storage.read(key: _privKeyAlias) as String?;
    if (privRaw == null) {
      throw StateError('Device identity not initialised — call getOrCreate first');
    }
    final priv = base64Url.decode(privRaw);
    final pair = await _algo.newKeyPairFromSeed(priv);
    final sig = await _algo.sign(message, keyPair: pair);
    return sig.bytes;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/crypto/device_identity_service_test.dart`
Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/crypto/device_identity_service.dart test/core/crypto/device_identity_service_test.dart
git commit -m "feat(c1): DeviceIdentityService — Ed25519 keypair per install"
```

---

## Task 8: InviteCodeService

Generates 40-bit Crockford codes (`XXXX-XXXX`), hashes them with BLAKE2b for server storage, and provides Argon2id wrap/unwrap of `K_family` using the code as the password.

**Files:**
- Create: `lib/core/crypto/invite_code_service.dart`
- Create: `test/core/crypto/invite_code_service_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/core/crypto/invite_code_service_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dreambook/core/crypto/invite_code_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InviteCodeService service;

  setUp(() {
    service = InviteCodeService();
  });

  group('InviteCodeService', () {
    test('generateCode() returns 8 Crockford chars in XXXX-XXXX form', () async {
      for (var i = 0; i < 100; i++) {
        final code = service.generateCode();
        expect(code.length, 9, reason: '8 chars + 1 dash');
        expect(code[4], '-');
        final stripped = code.replaceAll('-', '');
        expect(stripped.length, 8);
        expect(RegExp(r'^[0-9A-HJKMNP-TV-Z]+$').hasMatch(stripped), isTrue,
            reason: 'code $code must be Crockford-only');
      }
    });

    test('hashCode produces stable BLAKE2b digest', () async {
      final h1 = await service.hashCode_('MK29-HFX4');
      final h2 = await service.hashCode_('MK29-HFX4');
      expect(h1, h2);
      final h3 = await service.hashCode_('MK29-HFX5');
      expect(h1, isNot(equals(h3)));
    });

    test('hashCode normalises lower-case + ambiguous chars before hashing', () async {
      final h1 = await service.hashCode_('MK29-HFX4');
      final h2 = await service.hashCode_('mk29-hfx4');
      final h3 = await service.hashCode_('MK29HFX4');           // no dash
      final h4 = await service.hashCode_('MKO9-HfXi');          // O→0, l/I→1 collapsed; should NOT match unless code itself uses those
      expect(h1, h2);
      expect(h1, h3);
      expect(h1, isNot(equals(h4)),
          reason: 'normalisation does not change the code value, only formatting');
    });

    test('wrap then unwrap K_family round-trips', () async {
      final code = 'TEST-CODE'; // 8 valid Crockford chars w/ dash
      final familyKey = Uint8List.fromList(
        List<int>.generate(32, (i) => i),
      );
      final familyId = 'fam-abc-123';
      final wrapped = await service.wrapFamilyKey(
        code: code,
        familyKey: familyKey,
        familyId: familyId,
      );
      expect(wrapped.salt.length, 16);
      expect(wrapped.wrappedKeyEnvelope.length, greaterThan(32));
      final back = await service.unwrapFamilyKey(
        code: code,
        salt: wrapped.salt,
        wrappedKeyEnvelope: wrapped.wrappedKeyEnvelope,
        familyId: familyId,
      );
      expect(back, familyKey);
    });

    test('unwrap fails on wrong code', () async {
      final familyKey = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final familyId = 'fam-1';
      final wrapped = await service.wrapFamilyKey(
        code: 'TEST-CODE',
        familyKey: familyKey,
        familyId: familyId,
      );
      expect(
        () => service.unwrapFamilyKey(
          code: 'WRNG-CODE',
          salt: wrapped.salt,
          wrappedKeyEnvelope: wrapped.wrappedKeyEnvelope,
          familyId: familyId,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/crypto/invite_code_service_test.dart`
Expected: FAIL (file not found).

- [ ] **Step 3: Implement InviteCodeService**

Create `lib/core/crypto/invite_code_service.dart`:

```dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'crockford_base32.dart';
import 'crypto_envelope.dart';

/// Output of wrap step — the two values the server needs to store in
/// the `invites` table (alongside family_id, expiry, etc.).
class WrappedFamilyKey {
  const WrappedFamilyKey({required this.salt, required this.wrappedKeyEnvelope});

  final Uint8List salt; // 16 bytes
  final Uint8List wrappedKeyEnvelope; // CryptoEnvelope output
}

/// Per spec §3.1 / §5.2:
/// - code = Crockford base32 of 40 random bits → "XXXX-XXXX"
/// - hash for server = BLAKE2b(normalised(code))
/// - KDF = Argon2id m=64 MiB, t=3, p=1, len=32
/// - wrap = AES-GCM(K_kdf, K_family, aad=family_id)
class InviteCodeService {
  InviteCodeService({
    Argon2id? kdf,
    CryptoEnvelope? envelope,
    Random? rng,
  })  : _kdf = kdf ?? _defaultKdf(),
        _envelope = envelope ?? CryptoEnvelope(),
        _rng = rng ?? Random.secure();

  final Argon2id _kdf;
  final CryptoEnvelope _envelope;
  final Random _rng;

  static Argon2id _defaultKdf() => Argon2id(
        memory: 65536, // 64 MiB
        parallelism: 1,
        iterations: 3,
        hashLength: 32,
      );

  /// Generates an 8-character Crockford code formatted "XXXX-XXXX".
  String generateCode() {
    final bytes = Uint8List.fromList(
      List<int>.generate(5, (_) => _rng.nextInt(256)),
    );
    final raw = CrockfordBase32.encode(bytes); // 8 chars
    return '${raw.substring(0, 4)}-${raw.substring(4, 8)}';
  }

  /// BLAKE2b(normalised(code)). The normaliser strips dashes/whitespace
  /// and uppercases — so the hash matches whether the user typed
  /// "MK29-HFX4", "mk29hfx4", or "MK29 HFX4".
  ///
  /// Named with a trailing underscore to avoid clashing with Object.hashCode.
  Future<Uint8List> hashCode_(String code) async {
    final normalised = _normalise(code);
    final hasher = Blake2b();
    final hash = await hasher.hash(utf8.encode(normalised));
    return Uint8List.fromList(hash.bytes);
  }

  /// Wraps [familyKey] under a key derived from [code] + a fresh 16-byte salt.
  /// AAD = familyId so a wrapped blob cannot be replayed across families.
  Future<WrappedFamilyKey> wrapFamilyKey({
    required String code,
    required Uint8List familyKey,
    required String familyId,
  }) async {
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => _rng.nextInt(256)),
    );
    final kdfKey = await _deriveKey(code: code, salt: salt);
    final wrapped = await _envelope.seal(
      familyKey,
      kdfKey,
      utf8.encode(familyId),
    );
    return WrappedFamilyKey(salt: salt, wrappedKeyEnvelope: wrapped);
  }

  /// Reverses [wrapFamilyKey]. Throws SecretBoxAuthenticationError on bad code,
  /// bad salt, modified envelope, or mismatched familyId.
  Future<Uint8List> unwrapFamilyKey({
    required String code,
    required Uint8List salt,
    required Uint8List wrappedKeyEnvelope,
    required String familyId,
  }) async {
    final kdfKey = await _deriveKey(code: code, salt: salt);
    return _envelope.open(
      wrappedKeyEnvelope,
      kdfKey,
      utf8.encode(familyId),
    );
  }

  Future<SecretKey> _deriveKey({
    required String code,
    required Uint8List salt,
  }) async {
    final normalised = _normalise(code);
    return _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(normalised)),
      nonce: salt,
    );
  }

  String _normalise(String code) {
    return code.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/crypto/invite_code_service_test.dart`
Expected: 5 tests PASS. Argon2id-based tests may take ~2-3 s each on first run — that is expected.

- [ ] **Step 5: Commit**

```bash
git add lib/core/crypto/invite_code_service.dart test/core/crypto/invite_code_service_test.dart
git commit -m "feat(c1): InviteCodeService — Crockford code gen + BLAKE2b hash + Argon2id wrap"
```

---

## Task 9: Migration m003_v3

Adds `family_id` + `key_version` to every syncable table, creates `family_metadata` and `key_rotation_state` tables, adds `device_pub_key` to `caregiver`. Backfills `family_id` for existing rows with a single auto-generated UUID stored in `family_metadata`.

**Files:**
- Create: `lib/core/db/migrations/m003_v3.dart`
- Create: `test/core/db/migration_m003_test.dart`
- Modify: `lib/core/db/database_provider.dart`

- [ ] **Step 1: Write failing tests**

Create `test/core/db/migration_m003_test.dart`:

```dart
import 'package:dreambook/core/db/migrations/m001_initial.dart';
import 'package:dreambook/core/db/migrations/m002_v2.dart';
import 'package:dreambook/core/db/migrations/m003_v3.dart';
import 'package:dreambook/core/db/migrations/migrations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (d, _) async {
          await Migrations([m001Initial, m002V2]).runAll(d);
        },
      ),
    );
  });

  tearDown(() => db.close());

  test('adds family_id and key_version columns to every syncable table', () async {
    await m003V3(db);
    final tables = [
      'baby', 'caregiver', 'pump_session', 'stash_bottle',
      'feed', 'diaper', 'sleep', 'vaccination',
    ];
    for (final t in tables) {
      final info = await db.rawQuery('PRAGMA table_info($t)');
      final cols = info.map((r) => r['name'] as String).toSet();
      expect(cols, contains('family_id'),
          reason: 'family_id missing on $t');
      expect(cols, contains('key_version'),
          reason: 'key_version missing on $t');
    }
  });

  test('creates family_metadata + key_rotation_state tables', () async {
    await m003V3(db);
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    final names = tables.map((r) => r['name'] as String).toSet();
    expect(names, contains('family_metadata'));
    expect(names, contains('key_rotation_state'));
  });

  test('backfills existing rows with same family_id from family_metadata', () async {
    // Seed a baby in v2 schema.
    await db.insert('baby', {
      'id': 'b1',
      'name': 'Mali',
      'dob': '2026-03-01',
      'preferred_unit': 'oz',
      'created_at': '2026-05-13T00:00:00.000Z',
      'updated_at': '2026-05-13T00:00:00.000Z',
      'version': 1,
    });
    await m003V3(db);
    final meta = await db.query('family_metadata');
    expect(meta.length, 1);
    final familyId = meta.first['id'] as String;
    final babies = await db.query('baby');
    expect(babies.first['family_id'], familyId);
    expect(babies.first['key_version'], 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/db/migration_m003_test.dart`
Expected: FAIL (`m003_v3.dart` not found).

- [ ] **Step 3: Implement m003_v3**

Create `lib/core/db/migrations/m003_v3.dart`:

```dart
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

/// v2 → v3.
///
/// Adds `family_id` + `key_version` columns to every syncable table
/// (per spec §3.1) and creates `family_metadata` + `key_rotation_state`.
/// Existing rows are backfilled with a single newly-generated `family_id`
/// representing the upgrading user's family. `device_pub_key` column is
/// added to `caregiver` for the handshake fan-out flow.
Future<void> m003V3(Database db) async {
  final syncable = const [
    'baby',
    'caregiver',
    'pump_session',
    'stash_bottle',
    'feed',
    'diaper',
    'sleep',
    'vaccination',
  ];

  // 1. Generate one family_id for the existing local family (if any rows exist).
  final uuid = const Uuid().v4();
  final now = DateTime.now().toUtc().toIso8601String();

  // 2. Add new columns to every syncable table.
  await db.transaction((txn) async {
    for (final t in syncable) {
      await txn.execute("ALTER TABLE $t ADD COLUMN family_id TEXT NOT NULL DEFAULT ''");
      await txn.execute("ALTER TABLE $t ADD COLUMN key_version INTEGER NOT NULL DEFAULT 1");
    }

    // 3. Caregiver gains device_pub_key column (populated at handshake).
    await txn.execute('ALTER TABLE caregiver ADD COLUMN device_pub_key BLOB');

    // 4. New tables.
    await txn.execute('''
      CREATE TABLE family_metadata (
        id TEXT PRIMARY KEY,
        current_key_version INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');
    await txn.execute('''
      CREATE TABLE key_rotation_state (
        family_id TEXT PRIMARY KEY,
        target_key_version INTEGER NOT NULL,
        started_at TEXT NOT NULL,
        last_processed_row TEXT
      )
    ''');

    // 5. Backfill family_id for existing rows if any data is present.
    final anyBaby = await txn.rawQuery('SELECT COUNT(*) AS c FROM baby');
    final count = (anyBaby.first['c'] as int?) ?? 0;
    if (count > 0) {
      await txn.insert('family_metadata', {
        'id': uuid,
        'current_key_version': 1,
        'created_at': now,
      });
      for (final t in syncable) {
        await txn.update(t, {'family_id': uuid});
      }
    }
  });
}
```

- [ ] **Step 4: Register m003V3 in database_provider**

Modify `lib/core/db/database_provider.dart`:

Find the existing line:
```dart
Migrations([m001Initial, m002V2])
```

Add an import for `m003_v3.dart`:
```dart
import 'package:dreambook/core/db/migrations/m003_v3.dart';
```

Change the migrations registration to:
```dart
Migrations([m001Initial, m002V2, m003V3])
```

Bump the `version: 2` argument on `openDatabase(...)` to `version: 3` and adjust the upgrade path so existing v1/v2 installs run `m003V3` via `onUpgrade` (the same pattern Plan B used for v1 → v2).

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/core/db/migration_m003_test.dart`
Expected: 3 tests PASS.

- [ ] **Step 6: Run the full test suite to catch any Plan B regression**

Run: `flutter test`
Expected: all tests PASS (Plan B 90 + new ones). If any Plan B repo test fails because it loads with `m001Initial + m002V2` only, update those test fixtures to include `m003V3` in their `Migrations([...])` list.

- [ ] **Step 7: Commit**

```bash
git add lib/core/db/migrations/m003_v3.dart lib/core/db/database_provider.dart \
        test/core/db/migration_m003_test.dart
# Also commit any Plan B test-fixture updates required by Step 6.
git commit -m "feat(c1): migration m003 — family_id + key_version + family_metadata + key_rotation_state"
```

---

## Task 10: KeyRotationService (orchestrator)

Pure orchestration logic only — no network calls in C-1. C-2 will inject the Supabase client. The service tracks rotation state in `key_rotation_state` so a mid-flight crash can resume.

**Files:**
- Create: `lib/core/crypto/key_rotation_service.dart`
- Create: `test/core/crypto/key_rotation_service_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/core/crypto/key_rotation_service_test.dart`:

```dart
import 'package:dreambook/core/crypto/family_key_service.dart';
import 'package:dreambook/core/crypto/key_rotation_service.dart';
import 'package:dreambook/core/db/migrations/m001_initial.dart';
import 'package:dreambook/core/db/migrations/m002_v2.dart';
import 'package:dreambook/core/db/migrations/m003_v3.dart';
import 'package:dreambook/core/db/migrations/migrations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../_fakes/in_memory_secure_storage.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  late Database db;
  late FamilyKeyService familyKeys;
  late KeyRotationService service;
  const familyId = 'fam-1';

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (d, _) async {
          await Migrations([m001Initial, m002V2, m003V3]).runAll(d);
        },
      ),
    );
    familyKeys = FamilyKeyService.forTest(InMemorySecureStorage());
    await familyKeys.generate(familyId: familyId, keyVersion: 1);
    await db.insert('family_metadata', {
      'id': familyId,
      'current_key_version': 1,
      'created_at': '2026-05-14T00:00:00.000Z',
    });
    service = KeyRotationService(db: db, familyKeys: familyKeys);
  });

  tearDown(() => db.close());

  group('KeyRotationService', () {
    test('beginRotation() writes key_rotation_state and bumps target version', () async {
      await service.beginRotation(familyId: familyId);
      final rows = await db.query('key_rotation_state', where: 'family_id = ?', whereArgs: [familyId]);
      expect(rows.length, 1);
      expect(rows.first['target_key_version'], 2);
    });

    test('completeRotation() updates family_metadata version and clears state', () async {
      await service.beginRotation(familyId: familyId);
      await service.completeRotation(familyId: familyId);
      final meta = await db.query('family_metadata', where: 'id = ?', whereArgs: [familyId]);
      expect(meta.first['current_key_version'], 2);
      final state = await db.query('key_rotation_state', where: 'family_id = ?', whereArgs: [familyId]);
      expect(state, isEmpty);
      final newKey = await familyKeys.read(familyId: familyId);
      expect(newKey!.keyVersion, 2);
    });

    test('resume() picks up an interrupted rotation and finishes it', () async {
      await service.beginRotation(familyId: familyId);
      // Simulate crash: do NOT call completeRotation.
      // New service instance models a fresh app launch.
      final fresh = KeyRotationService(db: db, familyKeys: familyKeys);
      await fresh.resumeIfNeeded(familyId: familyId);
      final meta = await db.query('family_metadata', where: 'id = ?', whereArgs: [familyId]);
      expect(meta.first['current_key_version'], 2);
      final state = await db.query('key_rotation_state', where: 'family_id = ?', whereArgs: [familyId]);
      expect(state, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/crypto/key_rotation_service_test.dart`
Expected: FAIL (file not found).

- [ ] **Step 3: Implement KeyRotationService**

Create `lib/core/crypto/key_rotation_service.dart`:

```dart
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'family_key_service.dart';

/// Orchestrates `K_family` rotation. Local state only — the network
/// portion (re-encrypt remote rows, fan out via X25519) lands in C-2.
///
/// Crash safety: [beginRotation] records intent in `key_rotation_state`
/// BEFORE generating the new key. [resumeIfNeeded] finishes any
/// outstanding rotation on next app launch.
class KeyRotationService {
  KeyRotationService({required this.db, required this.familyKeys});

  final Database db;
  final FamilyKeyService familyKeys;

  /// Begins rotation: bumps target version in `key_rotation_state`.
  /// Idempotent — calling twice in a row leaves a single row.
  Future<void> beginRotation({required String familyId}) async {
    final meta = await _readFamilyMetadata(familyId);
    final target = meta + 1;
    await db.insert(
      'key_rotation_state',
      {
        'family_id': familyId,
        'target_key_version': target,
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'last_processed_row': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Generates the new K_family, switches local state, and clears
  /// `key_rotation_state`. Bumps `family_metadata.current_key_version`.
  Future<void> completeRotation({required String familyId}) async {
    final state = await _readRotationState(familyId);
    if (state == null) {
      throw StateError('No rotation in progress for $familyId');
    }
    await familyKeys.rotate(familyId: familyId);
    await db.transaction((txn) async {
      await txn.update(
        'family_metadata',
        {'current_key_version': state},
        where: 'id = ?',
        whereArgs: [familyId],
      );
      await txn.delete(
        'key_rotation_state',
        where: 'family_id = ?',
        whereArgs: [familyId],
      );
    });
  }

  /// Called on app launch. If an interrupted rotation exists, finish it.
  Future<void> resumeIfNeeded({required String familyId}) async {
    final state = await _readRotationState(familyId);
    if (state == null) return;
    await completeRotation(familyId: familyId);
  }

  Future<int> _readFamilyMetadata(String familyId) async {
    final rows = await db.query(
      'family_metadata',
      where: 'id = ?',
      whereArgs: [familyId],
    );
    if (rows.isEmpty) {
      throw StateError('No family_metadata row for $familyId');
    }
    return rows.first['current_key_version'] as int;
  }

  Future<int?> _readRotationState(String familyId) async {
    final rows = await db.query(
      'key_rotation_state',
      where: 'family_id = ?',
      whereArgs: [familyId],
    );
    if (rows.isEmpty) return null;
    return rows.first['target_key_version'] as int;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/crypto/key_rotation_service_test.dart`
Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/crypto/key_rotation_service.dart test/core/crypto/key_rotation_service_test.dart
git commit -m "feat(c1): KeyRotationService — local orchestration + crash-resume"
```

---

## Task 11: Build hardening (ProGuard + obfuscate doc + iOS accessibility)

Per spec §6.1 items 2, 10, 12. The build flag itself is invoked at `flutter build` time (no gradle change), but we need ProGuard rules so release builds don't strip `sqflite_sqlcipher` / `flutter_secure_storage` JNI lookups.

**Files:**
- Create: `android/app/proguard-rules.pro`
- Create: `docs/build-flags.md`
- Modify: `android/app/build.gradle` (link ProGuard file in release config)
- Modify: `lib/core/services/secure_key_service.dart` (override iOS accessibility)

- [ ] **Step 1: Create ProGuard rules**

Create `android/app/proguard-rules.pro`:

```
# Plan C-1 hardening (per spec §6.1 item 2).
# Keep classes accessed via JNI / reflection so release R8 doesn't strip them.

# sqflite_sqlcipher
-keep class net.zetetic.database.** { *; }
-keep class com.tekartik.sqflite.** { *; }
-keep class com.davidmedenjak.sqfliteSqlcipher.** { *; }

# flutter_secure_storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# purchases_flutter (Plan D dep; safe to keep now to avoid forgetting later)
-keep class com.revenuecat.** { *; }

# Cryptography (Dart) bridges
-keep class io.flutter.plugin.** { *; }

# Generic safety — don't obfuscate Flutter plugin glue layer
-keep class * extends io.flutter.embedding.engine.plugins.FlutterPlugin { *; }
-keep class * extends io.flutter.embedding.engine.plugins.activity.ActivityAware { *; }
```

- [ ] **Step 2: Link ProGuard file in release config**

Modify `android/app/build.gradle`. Inside `android { buildTypes { release { ... } } }`, add or modify the `release` block to include:

```gradle
        release {
            signingConfig signingConfigs.debug  // adjust at signing time
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
```

If the block already exists without `proguardFiles`, append that line. If `minifyEnabled` is already false, leave it false until signing config is real — but the ProGuard file is loaded only when minifyEnabled is true, so this is forward-compatible.

- [ ] **Step 3: Create build-flags doc**

Create `docs/build-flags.md`:

```markdown
# DreamBook build flags

## Release-only mandatory flags (per spec §6.1 item 2)

When building APK / IPA for release:

```bash
flutter build apk --release --obfuscate --split-debug-info=build/symbols
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
flutter build ios --release --obfuscate --split-debug-info=build/symbols
```

`--obfuscate` and `--split-debug-info` together rewrite Dart symbol names
and emit a `.symbols` file in `build/symbols/` for later crash decoding.
Without these flags, function/class names are visible in `strings` / apktool
analysis of the binary.

## ProGuard

Android release builds use `android/app/proguard-rules.pro` (linked from
`android/app/build.gradle` `release { proguardFiles ... }`). Keep rules cover
sqflite_sqlcipher, flutter_secure_storage, purchases_flutter, and Flutter
plugin glue.

## Symbols storage

`build/symbols/` is gitignored. Upload to Crashlytics (Plan F) or archive
internally per release tag for crash decoding.
```

- [ ] **Step 4: Override iOS Keychain accessibility on SecureKeyService**

Modify `lib/core/services/secure_key_service.dart`. Find:
```dart
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
```

Replace with:
```dart
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device_only,
    ),
  );
```

This applies the auditor #2 recommendation (spec §6.1 item 10): keep the DB key on the device, never sync to iCloud Keychain.

- [ ] **Step 5: Run analyze + full test suite**

```bash
flutter analyze
flutter test
```

Expected: analyze clean; all tests still pass.

- [ ] **Step 6: Commit**

```bash
git add android/app/proguard-rules.pro android/app/build.gradle \
        docs/build-flags.md lib/core/services/secure_key_service.dart
git commit -m "chore(c1): ProGuard rules + obfuscate doc + iOS Keychain device-only"
```

---

## Task 12: Manifest security check + final verification + tag

Per spec §6.1 item 11: a static check that the Android manifest contains no exported components and no `sharedUserId` declaration.

**Files:**
- Create: `tool/check_manifest_security.sh`

- [ ] **Step 1: Create the check script**

Create `tool/check_manifest_security.sh`:

```bash
#!/usr/bin/env bash
# Verifies AndroidManifest.xml ships with no exported components and no
# sharedUserId — both increase the local-attack surface (spec §6.1 item 11).
set -euo pipefail

MANIFEST="android/app/src/main/AndroidManifest.xml"

if [[ ! -f "$MANIFEST" ]]; then
  echo "FAIL: $MANIFEST not found"
  exit 1
fi

if grep -E 'android:sharedUserId=' "$MANIFEST" > /dev/null; then
  echo "FAIL: android:sharedUserId is forbidden in $MANIFEST"
  exit 1
fi

# Look for exported components other than the LAUNCHER activity which
# legitimately must be exported.
exported_lines=$(grep -nE 'android:exported="true"' "$MANIFEST" || true)
if [[ -n "$exported_lines" ]]; then
  # Each exported="true" must be on a line whose enclosing component is
  # the LAUNCHER activity. Approximate check: require the same file to
  # contain MAIN/LAUNCHER on a line within 10 lines of each exported flag.
  while IFS= read -r match; do
    line_no="${match%%:*}"
    start=$((line_no > 10 ? line_no - 10 : 1))
    end=$((line_no + 10))
    block=$(sed -n "${start},${end}p" "$MANIFEST")
    if ! grep -qE 'android.intent.action.MAIN' <<<"$block"; then
      echo "FAIL: exported component on line $line_no is not a LAUNCHER activity"
      echo "Context:"
      echo "$block"
      exit 1
    fi
  done <<<"$exported_lines"
fi

echo "OK: manifest security check passed"
```

- [ ] **Step 2: Make the script executable + run it**

```bash
chmod +x tool/check_manifest_security.sh
./tool/check_manifest_security.sh
```

Expected: `OK: manifest security check passed`.

If it fails, audit `android/app/src/main/AndroidManifest.xml` and remove any unnecessary exported components or `sharedUserId` declaration before continuing.

- [ ] **Step 3: Run all verification commands**

```bash
flutter analyze
flutter test
tool/check_no_exact_alarms.sh
tool/check_manifest_security.sh
```

Expected:
- `flutter analyze` → No issues found
- `flutter test` → All tests pass (Plan B 90 + Plan C-1 ≥30 = ≥120 total)
- `tool/check_no_exact_alarms.sh` → OK
- `tool/check_manifest_security.sh` → OK

If any fails, fix the underlying issue before committing.

- [ ] **Step 4: Commit + tag**

```bash
git add tool/check_manifest_security.sh
git commit -m "chore(c1): manifest security static check"
git tag plan-c1-crypto-complete
git log --oneline -15
```

Expected: tag `plan-c1-crypto-complete` exists on the latest commit; `git log` shows the 12 task commits sitting on top of `plan-b-complete`.

- [ ] **Step 5: Optional — push branch + tag**

```bash
# Only if the user explicitly asks to push.
# git push -u origin feat/plan-c-1-crypto
# git push --tags
```

Push is not part of the plan — confirm with the human first.

---

## Acceptance gate (end of Plan C-1)

Before declaring C-1 done and moving to C-2:

1. `flutter analyze` → clean.
2. `flutter test` → all tests pass; new tests ≥ 30; total ≥ 120.
3. `tool/check_no_exact_alarms.sh` → OK.
4. `tool/check_manifest_security.sh` → OK.
5. Tag `plan-c1-crypto-complete` exists on the head of `feat/plan-c-1-crypto`.
6. No network code added (visual spot-check: nothing under `lib/core/sync/` or `lib/core/crypto/` imports `supabase_flutter`, `http`, `dio`, or `dart:io.HttpClient`).
7. No new dependency beyond `cryptography` and `cryptography_flutter`.

If any of those fail, do not proceed to C-2.

---

## Follow-up plans

- `2026-05-?-plan-c2-sync.md` — Supabase wiring, sync worker, RLS, Edge Functions, key rotation network flow. Drafted after C-1 lands.
- `2026-05-?-plan-c3-invite.md` — UI, QR, deep links, freerasp, caregivers list. Drafted after C-2 lands.

Each subsequent plan starts from the tip of its predecessor (`plan-c1-crypto-complete` → `plan-c2-sync-complete` → `plan-c3-invite-complete`).
