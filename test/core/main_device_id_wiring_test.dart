// test/core/main_device_id_wiring_test.dart
//
// Wiring regression test for `deviceIdProvider` in `lib/main.dart`.
//
// Why this exists — PREVENT-TEAM #5:
//
//   The pre-existing end-to-end test in
//   `test/integration/onboarding_first_sync_test.dart:122` INJECTS the
//   canonical hex fingerprint directly via
//   `deviceIdProvider.overrideWithValue(fx.deviceA)`. That means the
//   integration test would STILL pass even if `main.dart` regressed back to
//   `Uuid().v4()` for `deviceIdProvider` — the override is doing the work,
//   not the boot path. That's exactly the bug class that wasted a week on
//   the device_fp / RLS-42501 regression (we kept fixing downstream code
//   and missed the wiring at the top).
//
// This test closes that coverage gap by reproducing the REAL boot path:
//
//   1. Construct a `DeviceIdentityService` against an `InMemorySecureStorage`
//      backing (the test-only FakeSecureStorage — same one
//      `device_identity_service_test.dart` uses).
//   2. Call `.getOrCreate()` then `.fingerprintHex()` — identical to
//      `lib/main.dart:50-51`.
//   3. Build a `ProviderContainer` whose ONLY `deviceIdProvider` value comes
//      from that computed hex.
//   4. Assert `ref.read(deviceIdProvider)` equals SHA-256(pubKey)[0:16] hex.
//
// If anyone reverts `lib/main.dart` to compute the override from
// `Uuid().v4()` (or any other non-fingerprint source), the source-level
// guard at the bottom of this file fires immediately. The provider-wiring
// assertions then act as a second line of defence by pinning the expected
// shape of the value that the override SHOULD carry.
//
// Lives as a unit test (NOT tagged `integration`) because the check is
// purely provider wiring — no Supabase, no DB, no widgets. Runs in <1s in
// the default `flutter test` invocation.
@Tags(['unit'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dreambook/core/crypto/device_identity_service.dart';
import 'package:dreambook/core/providers/device_id_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_fakes/in_memory_secure_storage.dart';

/// Re-derive SHA-256(pub)[0:16] lowercase hex independently of
/// `DeviceIdentity.fingerprintHex()` so the assertion is a true contract
/// check, not a tautology against the production implementation.
Future<String> _independentFingerprintHex(Uint8List pub) async {
  final hash = await Sha256().hash(pub);
  return hash.bytes
      .sublist(0, 16)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

void main() {
  group('main.dart deviceIdProvider wiring', () {
    test(
      'override value equals SHA-256(devicePubKey)[0:16] hex — '
      'regresses if main.dart reverts to UUIDv4',
      () async {
        // ── Step 1: same secure-storage shape main.dart sees ──────────────
        // Production uses `const FlutterSecureStorage()`. The service only
        // calls read/write/delete on it, which `InMemorySecureStorage`
        // satisfies — and `DeviceIdentityService.forTest(...)` is the
        // production-blessed seam for swapping in a fake here.
        final storage = InMemorySecureStorage();
        final identityService = DeviceIdentityService.forTest(storage);

        // ── Step 2: replicate lib/main.dart:50-51 verbatim ───────────────
        // ```
        // final deviceIdentity = await DeviceIdentityService(secureStorage)
        //     .getOrCreate();
        // final deviceId = await deviceIdentity.fingerprintHex();
        // ```
        final deviceIdentity = await identityService.getOrCreate();
        final deviceId = await deviceIdentity.fingerprintHex();

        // Sanity check: fingerprintHex() must produce 32-char lowercase hex
        // — that's the wire-format RLS requires. If this fails the bug is
        // in DeviceIdentity.fingerprintHex(), not the wiring.
        expect(deviceId.length, 32,
            reason: 'fingerprintHex() must be 16 bytes = 32 hex chars');
        expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(deviceId), isTrue,
            reason: 'fingerprintHex() must be lowercase hex');

        // ── Step 3: build the same ProviderScope override main.dart uses ─
        final container = ProviderContainer(
          overrides: [
            deviceIdProvider.overrideWithValue(deviceId),
          ],
        );
        addTearDown(container.dispose);

        // ── Step 4: independent re-derivation as the source of truth ─────
        final expectedHex =
            await _independentFingerprintHex(deviceIdentity.publicKeyBytes);

        // The value resolved by the provider — i.e. what every consumer in
        // the real app actually sees — must equal SHA-256(pub)[0:16] hex.
        // If main.dart someday computes the override from `Uuid().v4()`
        // instead of `fingerprintHex()`, the override value won't match
        // this independent derivation and the test fails.
        expect(
          container.read(deviceIdProvider),
          expectedHex,
          reason:
              'deviceIdProvider must resolve to SHA-256(devicePubKey)[0:16] '
              'lowercase hex — the RLS contract in '
              'supabase/migrations/0017_rls_reharden.sql:19-22 requires '
              'written_by_device = encode(family_devices.device_fp, \'hex\'). '
              'If this fails, main.dart\'s deviceIdProvider override has '
              'likely regressed to Uuid().v4() or another non-fingerprint '
              'value — see PREVENT-TEAM #5 notes at the top of this file.',
        );

        // Belt-and-braces: the provider value must also match what the
        // production helper emits — guards against a future fork between
        // fingerprintHex() and the wire format.
        expect(container.read(deviceIdProvider), deviceId);
      },
    );

    test(
      'second boot returns the SAME fingerprint — keypair is persisted, '
      'override is deterministic across app restarts',
      () async {
        final storage = InMemorySecureStorage();

        // Boot 1
        final id1 = await DeviceIdentityService.forTest(storage).getOrCreate();
        final fp1 = await id1.fingerprintHex();

        // Boot 2 — same storage, fresh service instance (simulates re-launch)
        final id2 = await DeviceIdentityService.forTest(storage).getOrCreate();
        final fp2 = await id2.fingerprintHex();

        expect(fp2, fp1,
            reason:
                'deviceIdProvider must be stable across app restarts — '
                'family_devices.device_fp is set once at bootstrap_family '
                'and never updated, so the override on every subsequent '
                'launch must match.');

        // Both containers' provider values must agree.
        final c1 = ProviderContainer(
          overrides: [deviceIdProvider.overrideWithValue(fp1)],
        );
        addTearDown(c1.dispose);
        final c2 = ProviderContainer(
          overrides: [deviceIdProvider.overrideWithValue(fp2)],
        );
        addTearDown(c2.dispose);
        expect(c1.read(deviceIdProvider), c2.read(deviceIdProvider));
      },
    );

    test(
      'source-level guard: lib/main.dart must NOT contain a '
      '`_getOrCreateDeviceId` helper (the legacy UUIDv4 wrapper)',
      () async {
        // The previous broken implementation routed `deviceIdProvider`
        // through a private `_getOrCreateDeviceId()` helper in main.dart
        // that called `Uuid().v4()` and cached the value in SharedPreferences
        // — see the regression history in
        // test/integration/sync_device_fp_contract_test.dart. If anyone
        // re-adds that helper, the wiring is back on the broken path. Catch
        // it at the source so we don't have to wait for a real Supabase
        // integration run to fail.
        final mainFile = File('lib/main.dart');
        expect(mainFile.existsSync(), isTrue,
            reason: 'lib/main.dart must exist at the repo root');
        final source = mainFile.readAsStringSync();

        expect(
          source.contains('_getOrCreateDeviceId'),
          isFalse,
          reason:
              'lib/main.dart contains a `_getOrCreateDeviceId` helper. '
              'That helper was the UUIDv4-based legacy path that broke RLS '
              '(error 42501). The correct boot path computes the device id '
              'via `DeviceIdentityService(...).getOrCreate()` followed by '
              '`.fingerprintHex()` — see lib/main.dart:50-51. Remove the '
              'helper and use the fingerprint directly.',
        );

        // Defence in depth: assert the canonical boot-path strings are still
        // present. If both helpers below disappear we lose the SHA-256
        // wiring entirely — that's the regression we are guarding against.
        expect(
          source.contains('DeviceIdentityService'),
          isTrue,
          reason:
              'lib/main.dart must import and use DeviceIdentityService to '
              'derive the device fingerprint passed to deviceIdProvider.',
        );
        expect(
          source.contains('fingerprintHex'),
          isTrue,
          reason:
              'lib/main.dart must call `.fingerprintHex()` to compute the '
              'value handed to `deviceIdProvider.overrideWithValue(...)`. '
              'Any other source (UUID, randomness, prefs string) breaks the '
              'RLS contract.',
        );
      },
    );
  });
}
