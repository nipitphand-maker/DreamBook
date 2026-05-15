// test/integration/families_select_rls_regression_test.dart
//
// PREVENT-TEAM #4 — server-side regression test for the families_select RLS
// bug fixed in supabase/migrations/0026_fix_families_select_uuid_send_bug.sql.
//
// The bug:
//   The original families_select policy (0002_rls.sql) compared
//     family_devices.device_fp = uuid_send(auth.uid())
//   which is the same shape bug 0011/0016/0017 had to fix in
//   key_distribution / encrypted_rows — device_fp is SHA-256(pubkey)[0:16]
//   while uuid_send(auth.uid()) is the 16-byte UUID. They are NEVER equal.
//
//   Symptom in production:
//     * Authenticated user could not SELECT their own families row.
//     * encrypted_rows_insert WITH CHECK subquery
//         key_version = (SELECT current_key_version FROM families
//                        WHERE id = encrypted_rows.family_id)
//       returned NULL → `1 = NULL` → INSERT denied → Postgres 42501.
//     * Sync never pushed any rows even though every other identifier
//       (device_fp, auth_user_id, family_id) was correctly aligned.
//
// What this file does — 4 server-side regression tests that exercise the
// real Postgres RLS predicates against a local Supabase booted via
// `tool/test_supabase_start.sh`. They skip cleanly (markTestSkipped) when
// `.env.test.supabase` is absent (e.g. plain `flutter test`).
//
//   1. POSITIVE: GET families MUST return the caller's row when authed.
//      Direct catch for the families_select policy regression.
//
//   2. POSITIVE: encrypted_rows INSERT with all three WITH-CHECK conditions
//      satisfied MUST return 201 (no exception). Catches a regression of
//      ANY of the three predicates — including a re-broken families_select
//      that makes the key_version subquery return NULL.
//
//   3. NEGATIVE: encrypted_rows INSERT with key_version = 999 (mismatched)
//      MUST be rejected (42501). Proves the key_version condition is still
//      enforced — so a future "fix" that simply drops the check (e.g.
//      collapses the WITH CHECK to `family_id IN (...)`) is caught.
//
//   4. NEGATIVE: encrypted_rows INSERT with written_by_device set to a
//      random hex string MUST be rejected (42501). Proves the device_fp
//      predicate is still enforced.
//
// Read-only on production — uses the local-Supabase harness ONLY.

@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '_helpers/real_supabase_harness.dart';

void main() {
  RealSupabaseHarness? harness;

  setUpAll(() async {
    harness = await RealSupabaseHarness.bootOrSkip();
  });

  // ---------------------------------------------------------------------------
  // 1. POSITIVE — families_select policy: authed user can read their family.
  // ---------------------------------------------------------------------------
  test(
    'POSITIVE — GET families returns the caller\'s row '
    '(direct families_select policy probe)',
    () async {
      final h = harness;
      if (h == null) return; // .env.test.supabase missing → skipped
      final fx = await h.freshFamily();
      addTearDown(fx.dispose);

      // Device A is signed-in anonymously by the harness; its JWT carries
      // auth.uid() = authA.user.id. The harness inserted a family_devices row
      // with auth_user_id = authA.user.id, so current_user_family_ids() should
      // include fx.familyId — and families_select should let device A read it.
      final rows = await fx.clientA
          .from('families')
          .select('id, current_key_version')
          .eq('id', fx.familyId);

      expect(
        rows,
        isNotEmpty,
        reason:
            'families_select returned 0 rows for the authenticated caller. '
            'This is the EXACT symptom of the bug fixed in migration 0026 — '
            'the policy was comparing family_devices.device_fp against '
            'uuid_send(auth.uid()) (two unrelated 16-byte values). '
            'If this expectation fires, encrypted_rows INSERTs will start '
            'failing with 42501 in production because the WITH CHECK '
            'subquery for key_version will resolve to NULL.',
      );
      expect((rows as List).single['id'], fx.familyId);
      expect((rows).single['current_key_version'], 1);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // ---------------------------------------------------------------------------
  // 2. POSITIVE — well-formed encrypted_rows INSERT (all 3 WITH CHECK
  //    conditions satisfied) returns 201, not 42501.
  // ---------------------------------------------------------------------------
  test(
    'POSITIVE — encrypted_rows INSERT with valid family_id + matching '
    'device_fp + correct key_version returns 201 (no 42501)',
    () async {
      final h = harness;
      if (h == null) return;
      final fx = await h.freshFamily();
      addTearDown(fx.dispose);

      final bytes = TestRowBytes.deterministic('families-select-rls-pos');

      // This call wraps INSERT INTO encrypted_rows. If migration 0026 were
      // reverted, the key_version subquery inside the policy WITH CHECK would
      // see NULL (because families_select hides the row from the caller) and
      // the predicate `1 = NULL` would short-circuit to false → 42501.
      Object? caught;
      try {
        await fx.serverA.insertEncryptedRow(
          id: '00000000-0000-0000-0000-0000000000b1',
          familyId: fx.familyId,
          tableName: 'feed',
          recordId: 'feed-rls-positive',
          version: 1,
          keyVersion: 1, // matches families.current_key_version
          ciphertext: bytes.ciphertext,
          aadHash: bytes.aadHash,
          writtenByDevice: fx.deviceA, // matches family_devices.device_fp
          updatedAt: DateTime.now().toUtc(),
        );
      } catch (e) {
        caught = e;
      }

      expect(
        caught,
        isNull,
        reason:
            'Well-formed INSERT was rejected. If the error code is 42501, '
            'one of the three conditions in encrypted_rows_insert (see '
            '0017_rls_reharden.sql:17-32) has regressed: '
            '(a) family_id IN current_user_family_ids() — broken if '
            'current_user_family_ids() helper drifted; '
            '(b) written_by_device = encode(device_fp,\'hex\') — broken if '
            'device_fp/auth_user_id mapping regressed; '
            '(c) key_version = (SELECT current_key_version FROM families …) '
            '— broken if families_select hides the row (the bug 0026 fixed).',
      );

      // Confirm the row landed.
      final landed = await fx.serviceClient
          .from('encrypted_rows')
          .select('id, key_version, written_by_device')
          .eq('family_id', fx.familyId);
      expect(landed, hasLength(1));
      expect((landed as List).single['key_version'], 1);
      expect((landed).single['written_by_device'], fx.deviceA);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // ---------------------------------------------------------------------------
  // 3. NEGATIVE — key_version mismatch still rejected (42501).
  //    Proves the key_version condition is enforced. If a future "fix" to
  //    families_select accidentally also softens this check (e.g. drops it
  //    from the WITH CHECK), this test will catch it.
  // ---------------------------------------------------------------------------
  test(
    'NEGATIVE — encrypted_rows INSERT with mismatched key_version=999 '
    'rejected with 42501',
    () async {
      final h = harness;
      if (h == null) return;
      final fx = await h.freshFamily();
      addTearDown(fx.dispose);

      final bytes = TestRowBytes.deterministic('families-select-rls-neg-kv');

      Object? caught;
      try {
        await fx.serverA.insertEncryptedRow(
          id: '00000000-0000-0000-0000-0000000000b2',
          familyId: fx.familyId,
          tableName: 'feed',
          recordId: 'feed-rls-bad-kv',
          version: 1,
          keyVersion: 999, // family.current_key_version is 1
          ciphertext: bytes.ciphertext,
          aadHash: bytes.aadHash,
          writtenByDevice: fx.deviceA,
          updatedAt: DateTime.now().toUtc(),
        );
      } catch (e) {
        caught = e;
      }

      expect(
        caught,
        isA<PostgrestException>(),
        reason:
            'INSERT with stale key_version MUST be rejected by RLS. '
            'See encrypted_rows_insert WITH CHECK condition #3 in '
            '0017_rls_reharden.sql:27-31. If this fires green, the policy '
            'has been softened — INSERTs with stale keys would land on the '
            'server and a stale-K_family device could write ciphertext other '
            'devices cannot decrypt.',
      );
      final code = (caught as PostgrestException).code;
      expect(
        code,
        '42501',
        reason:
            'expected Postgres 42501 (insufficient_privilege) from RLS '
            'predicate, got code=$code message=${caught.message}',
      );

      // Nothing leaked.
      final leaked = await fx.serviceClient
          .from('encrypted_rows')
          .select('id')
          .eq('family_id', fx.familyId);
      expect(leaked, isEmpty,
          reason: 'no row should have been written despite the bad key_version');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // ---------------------------------------------------------------------------
  // 4. NEGATIVE — written_by_device mismatch still rejected (42501).
  //    Proves the device_fp condition is enforced. Random hex (not equal to
  //    family_devices.device_fp for the caller) MUST be rejected.
  // ---------------------------------------------------------------------------
  test(
    'NEGATIVE — encrypted_rows INSERT with random written_by_device '
    'rejected with 42501',
    () async {
      final h = harness;
      if (h == null) return;
      final fx = await h.freshFamily();
      addTearDown(fx.dispose);

      final bytes = TestRowBytes.deterministic('families-select-rls-neg-dev');

      // Generate a random 32-char hex string (16 bytes) — matches the FORMAT
      // of device_fp but is not registered for any device in this family.
      final u = const Uuid().v4().replaceAll('-', '');
      final randomHex = (u + u).substring(0, 32);
      expect(randomHex, isNot(fx.deviceA));
      expect(randomHex, isNot(fx.deviceB));

      Object? caught;
      try {
        await fx.serverA.insertEncryptedRow(
          id: '00000000-0000-0000-0000-0000000000b3',
          familyId: fx.familyId,
          tableName: 'feed',
          recordId: 'feed-rls-bad-dev',
          version: 1,
          keyVersion: 1,
          ciphertext: bytes.ciphertext,
          aadHash: bytes.aadHash,
          writtenByDevice: randomHex, // unknown device
          updatedAt: DateTime.now().toUtc(),
        );
      } catch (e) {
        caught = e;
      }

      expect(
        caught,
        isA<PostgrestException>(),
        reason:
            'INSERT with unknown written_by_device MUST be rejected by RLS. '
            'See encrypted_rows_insert WITH CHECK condition #2 in '
            '0017_rls_reharden.sql:19-26. If this fires green, the device_fp '
            'binding has been removed and any caller could attribute writes '
            'to any device_fp string they choose — breaking accountability '
            'and the spoofed-writer audit story.',
      );
      final code = (caught as PostgrestException).code;
      expect(
        code,
        '42501',
        reason:
            'expected Postgres 42501 (insufficient_privilege) from RLS '
            'predicate, got code=$code message=${caught.message}',
      );

      final leaked = await fx.serviceClient
          .from('encrypted_rows')
          .select('id')
          .eq('family_id', fx.familyId);
      expect(leaked, isEmpty,
          reason:
              'no row should have been written despite the unknown device_fp');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
