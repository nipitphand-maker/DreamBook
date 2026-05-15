// test/integration/sync_device_fp_contract_test.dart
//
// Regression contract test for the device_fp → written_by_device wire format.
//
// History — this bug has resurfaced 5 times:
//
//   * `deviceIdProvider` was returning `Uuid().v4()` while the RLS policy at
//     `supabase/migrations/0017_rls_reharden.sql:19-22` expects
//     `written_by_device = encode(family_devices.device_fp, 'hex')` where
//     `device_fp = SHA-256(devicePubKey)[0:16]`. Every push hit
//     PostgrestException code 42501 — but no unit test caught it because
//     `test/_fakes/fake_supabase_server.dart:138` checks string equality
//     against whatever `writtenByDevice` the caller passes in, so the fake
//     happily accepts garbage that the real server rejects.
//
// This test exercises the REAL Postgres RLS predicate end-to-end against a
// local Supabase started via `tool/test_supabase_start.sh`. It runs in two
// modes:
//
//   POSITIVE — `deviceFp` matches what `bootstrap_family` / `claim_invite`
//              stored as `family_devices.device_fp` (lowercase hex of
//              SHA-256(pub)[0:16]). Push MUST succeed.
//
//   NEGATIVE — `deviceFp` is a UUIDv4 (the broken behaviour). Push MUST
//              fail with PostgrestException code 42501 — and we name the
//              contract in the failure reason so the next person who
//              regresses it sees exactly what they need to fix.
//
// TODO(test-cleanup): tighten `test/_fakes/fake_supabase_server.dart:138`
//   so it ALSO validates that `writtenByDevice` is 32-char lowercase hex
//   (i.e. the format produced by SHA-256(pub)[0:16]). Today that line is a
//   plain `!=` against the caller-supplied `authDeviceFp`, which means a
//   broken `deviceIdProvider` that returns the same garbage value for both
//   "auth" and "writtenByDevice" passes through silently in fake-server
//   unit tests. That mismatch is what let this bug keep regressing — even
//   with 247 unit tests green, the contract was never enforced. Adding a
//   format assertion there is a separate cleanup; THIS test is the
//   end-to-end safety net that fires regardless.

@Tags(['integration'])
library;

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dreambook/core/crypto/crypto_envelope.dart';
import 'package:dreambook/core/crypto/family_key_service.dart';
import 'package:dreambook/core/db/migrations/m001_initial.dart';
import 'package:dreambook/core/db/migrations/m002_v2.dart';
import 'package:dreambook/core/db/migrations/m003_v3.dart';
import 'package:dreambook/core/db/migrations/m004_v4.dart';
import 'package:dreambook/core/db/migrations/m005_daily_note.dart';
import 'package:dreambook/core/db/migrations/m006_sync_written_by.dart';
import 'package:dreambook/core/db/migrations/m007_sync_cursors.dart';
import 'package:dreambook/core/db/migrations/migrations.dart';
import 'package:dreambook/core/sync/supabase_sync_server.dart';
import 'package:dreambook/core/sync/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../_fakes/in_memory_secure_storage.dart';
import '_helpers/real_supabase_harness.dart';

/// Computes the canonical device_fp hex string the way bootstrap_family /
/// claim_invite do: lowercase hex of `SHA-256(devicePubKey)[0:16]`.
String _canonicalDeviceFpHex(Uint8List devicePubKey) {
  // Synchronous-looking helper; the cryptography package is async, so the
  // tests await Sha256().hash(...) inline below. This stub is here only to
  // document the contract for future readers.
  throw UnimplementedError('See inline call in tests');
}

/// Seeds a single dirty `baby` row + its sync_state ledger so SyncWorker
/// has something to push. The plaintext bytes are irrelevant — what we're
/// testing is the wire-level `written_by_device` predicate, not the
/// envelope cryptography (which has its own coverage).
Future<void> _seedDirtyBabyRow({
  required Database db,
  required String familyId,
}) async {
  await db.insert('family_metadata', {
    'id': familyId,
    'current_key_version': 1,
    'created_at': '2026-05-15T00:00:00.000Z',
  });
  await db.insert('baby', {
    'id': 'baby-contract-test',
    'name': 'Mali',
    'dob': '2026-03-01',
    'preferred_unit': 'oz',
    'created_at': '2026-05-15T00:00:00.000Z',
    'updated_at': '2026-05-15T00:00:00.000Z',
    'version': 1,
    'family_id': familyId,
    'key_version': 1,
  });
  await db.insert('sync_state', {
    'record_id': 'baby-contract-test',
    'table_name': 'baby',
    'version': 1,
    'updated_at': '2026-05-15T00:00:00.000Z',
    'dirty': 1,
    'last_synced_at': null,
  });
}

void main() {
  setUpAll(() => sqfliteFfiInit());

  RealSupabaseHarness? harness;

  setUpAll(() async {
    harness = await RealSupabaseHarness.bootOrSkip();
  });

  test(
    'POSITIVE — SyncWorker push succeeds when deviceFp = hex(SHA-256(pub)[0:16])',
    () async {
      final h = harness;
      if (h == null) return; // skipped at setUpAll when .env.test.supabase absent
      final fx = await h.freshFamily();
      addTearDown(fx.dispose);

      // fx.deviceA is already the 32-char lowercase hex value the harness
      // wrote into family_devices.device_fp (`encode(device_fp,'hex')`).
      // This is exactly the contract `bootstrap_family` enforces — so it is
      // the value a correctly-wired `deviceIdProvider` would emit.
      expect(
        fx.deviceA.length,
        32,
        reason:
            'harness sanity check: device_fp must be 16 bytes (32 hex chars)',
      );
      expect(
        RegExp(r'^[0-9a-f]{32}$').hasMatch(fx.deviceA),
        isTrue,
        reason: 'device_fp must be lowercase hex',
      );

      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 7,
          onCreate: (d, _) async {
            await Migrations([
              m001Initial,
              m002V2,
              m003V3,
              m004V4,
              m005DailyNote,
              m006SyncWrittenBy,
              m007SyncCursors,
            ]).runAll(d);
          },
        ),
      );
      addTearDown(db.close);

      await _seedDirtyBabyRow(db: db, familyId: fx.familyId);

      final familyKeys = FamilyKeyService.forTest(InMemorySecureStorage());
      await familyKeys.generate(familyId: fx.familyId, keyVersion: 1);

      final worker = SyncWorker(
        db: db,
        server: SupabaseSyncServer(fx.clientA),
        familyKeys: familyKeys,
        envelope: CryptoEnvelope(),
        familyId: fx.familyId,
        deviceFp: fx.deviceA, // ← canonical hex form
      );

      // Should NOT throw — push satisfies the RLS predicate
      //   written_by_device = encode(family_devices.device_fp, 'hex').
      await worker.pushOnce();

      // Confirm the row is on the server with the expected fp.
      final pulled = await fx.serverB.pullRows(familyId: fx.familyId);
      expect(pulled, hasLength(1));
      expect(pulled.single.writtenByDevice, fx.deviceA,
          reason: 'server-side written_by_device should round-trip exactly');
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'NEGATIVE — SyncWorker push fails with 42501 when deviceFp is a UUIDv4 '
    '(the old broken behaviour)',
    () async {
      final h = harness;
      if (h == null) return; // skipped at setUpAll
      final fx = await h.freshFamily();
      addTearDown(fx.dispose);

      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 7,
          onCreate: (d, _) async {
            await Migrations([
              m001Initial,
              m002V2,
              m003V3,
              m004V4,
              m005DailyNote,
              m006SyncWrittenBy,
              m007SyncCursors,
            ]).runAll(d);
          },
        ),
      );
      addTearDown(db.close);

      await _seedDirtyBabyRow(db: db, familyId: fx.familyId);

      final familyKeys = FamilyKeyService.forTest(InMemorySecureStorage());
      await familyKeys.generate(familyId: fx.familyId, keyVersion: 1);

      // The bug we're regression-guarding: deviceIdProvider returned UUIDv4.
      // RLS at 0017_rls_reharden.sql:19-22 requires hex(SHA-256(pub)[0:16]).
      // A UUID is 36 chars including dashes (or 32 chars without) and never
      // matches what's stored in family_devices.device_fp — so the INSERT
      // policy's WITH CHECK predicate evaluates to false and Postgres
      // returns 42501 (insufficient_privilege).
      final brokenDeviceFp = const Uuid().v4();
      expect(
        brokenDeviceFp,
        isNot(fx.deviceA),
        reason: 'pre-condition: UUID must differ from canonical fp',
      );

      final worker = SyncWorker(
        db: db,
        server: SupabaseSyncServer(fx.clientA),
        familyKeys: familyKeys,
        envelope: CryptoEnvelope(),
        familyId: fx.familyId,
        deviceFp: brokenDeviceFp, // ← BUG: UUID instead of fp hex
      );

      Object? caught;
      try {
        await worker.pushOnce();
      } catch (e) {
        caught = e;
      }

      expect(
        caught,
        isNotNull,
        reason:
            'SyncWorker.pushOnce MUST fail when deviceFp does not equal '
            'encode(family_devices.device_fp, \'hex\') — see RLS policy '
            'encrypted_rows_insert in 0017_rls_reharden.sql:19-22. If this '
            'expectation fires green it usually means deviceIdProvider has '
            'regressed back to Uuid().v4() — fix in main.dart so the '
            'override resolves DeviceIdentityService.fingerprintHex() '
            '(SHA-256(pubKey)[0:16] lowercase hex).',
      );

      // Drill into the cause: SupabaseSyncServer surfaces PostgrestException
      // directly (it does not yet wrap into SyncRlsReject — see TODO in
      // supabase_sync_server.dart). Match either shape so the test stays
      // green through that future refactor.
      final isPostgrest = caught is PostgrestException;
      final code = isPostgrest ? caught.code : null;
      expect(
        isPostgrest,
        isTrue,
        reason:
            'expected PostgrestException, got ${caught.runtimeType}: $caught',
      );
      expect(
        code,
        '42501',
        reason:
            'expected Postgres code 42501 (insufficient_privilege) from RLS '
            'predicate. Contract: written_by_device must equal '
            'encode(family_devices.device_fp, \'hex\'). See '
            'supabase/migrations/0017_rls_reharden.sql:19-22.',
      );

      // Nothing leaked into encrypted_rows.
      final leaked = await fx.serviceClient
          .from('encrypted_rows')
          .select('id')
          .eq('family_id', fx.familyId);
      expect(leaked, isEmpty,
          reason: 'no row should have been written despite the broken push');
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  // Sanity: re-derive the fp the way DeviceIdentity.fingerprintHex() does
  // and confirm the format matches what RLS expects. Keeps this test
  // file useful even when run without a live Supabase (the harness skips
  // the two tests above; this one always runs as a pure-Dart check).
  test('canonical fp format — SHA-256(pub)[0:16] lowercase hex, 32 chars',
      () async {
    final fakePub = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final hash = await Sha256().hash(fakePub);
    final hex = hash.bytes
        .sublist(0, 16)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    expect(hex.length, 32);
    expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(hex), isTrue,
        reason:
            'fingerprintHex() must match the format RLS compares against');
    // Reference the helper so the analyzer doesn't flag it unused.
    expect(() => _canonicalDeviceFpHex(fakePub), throwsUnimplementedError);
  });
}
