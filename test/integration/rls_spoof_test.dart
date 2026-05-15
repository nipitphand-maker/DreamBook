// test/integration/rls_spoof_test.dart
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '_helpers/real_supabase_harness.dart';

void main() {
  RealSupabaseHarness? harness;

  setUpAll(() async {
    harness = await RealSupabaseHarness.bootOrSkip();
  });

  test('Scenario 2 — spoofed written_by_device rejected by RLS', () async {
    final h = harness;
    if (h == null) return; // skipped at setUpAll
    final fx = await h.freshFamily();
    addTearDown(fx.dispose);

    final bytes = TestRowBytes.deterministic('spoof-attempt');

    Object? caught;
    try {
      // Device A authenticated, but lies about who wrote the row (claims B).
      await fx.serverA.insertEncryptedRow(
        id: '00000000-0000-0000-0000-000000000099',
        familyId: fx.familyId,
        tableName: 'feed',
        recordId: 'feed-spoof',
        version: 1,
        keyVersion: 1,
        ciphertext: bytes.ciphertext,
        aadHash: bytes.aadHash,
        writtenByDevice: fx.deviceB, // ← spoof
        updatedAt: DateTime.now().toUtc(),
      );
    } catch (e) {
      caught = e;
    }

    expect(caught, isNotNull,
        reason: 'INSERT with spoofed written_by_device MUST be rejected by RLS');
    expect(caught, isA<PostgrestException>(),
        reason: 'Expect PostgrestException with 42501/403 from RLS predicate');

    // And nothing leaked into encrypted_rows.
    final leaked = await fx.serviceClient
        .from('encrypted_rows')
        .select('id')
        .eq('family_id', fx.familyId);
    expect(leaked, isEmpty,
        reason: 'no row should have been written despite the spoof attempt');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('Scenario 2b — stale key_version rejected by RLS', () async {
    final h = harness;
    if (h == null) return; // skipped at setUpAll
    final fx = await h.freshFamily();
    addTearDown(fx.dispose);

    final bytes = TestRowBytes.deterministic('stale-key');

    Object? caught;
    try {
      await fx.serverA.insertEncryptedRow(
        id: '00000000-0000-0000-0000-0000000000aa',
        familyId: fx.familyId,
        tableName: 'feed',
        recordId: 'feed-stale',
        version: 1,
        keyVersion: 99, // family.current_key_version is 1
        ciphertext: bytes.ciphertext,
        aadHash: bytes.aadHash,
        writtenByDevice: fx.deviceA,
        updatedAt: DateTime.now().toUtc(),
      );
    } catch (e) {
      caught = e;
    }
    expect(caught, isA<PostgrestException>());
  }, timeout: const Timeout(Duration(seconds: 30)));
}
