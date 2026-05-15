// test/integration/sync_two_device_test.dart
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';

import '_helpers/real_supabase_harness.dart';

void main() {
  RealSupabaseHarness? harness;

  setUpAll(() async {
    harness = await RealSupabaseHarness.bootOrSkip();
  });

  test('Scenario 1 — write on A, pull on B, ciphertext bytes match', () async {
    final h = harness;
    if (h == null) return; // skipped at setUpAll
    final fx = await h.freshFamily();
    addTearDown(fx.dispose);

    final bytes = TestRowBytes.deterministic('hello-bytea-2026-05-15');

    await fx.serverA.insertEncryptedRow(
      id: '00000000-0000-0000-0000-000000000001',
      familyId: fx.familyId,
      tableName: 'feed',
      recordId: 'feed-1',
      version: 1,
      keyVersion: 1,
      ciphertext: bytes.ciphertext,
      aadHash: bytes.aadHash,
      writtenByDevice: fx.deviceA,
      updatedAt: DateTime.now().toUtc(),
    );

    final pulled = await fx.serverB.pullRows(familyId: fx.familyId);

    expect(pulled, hasLength(1));
    final row = pulled.single;
    expect(row.tableName, 'feed');
    expect(row.recordId, 'feed-1');
    expect(row.version, 1);
    expect(row.keyVersion, 1);
    expect(row.writtenByDevice, fx.deviceA);
    // The bug: ciphertext came back base64 String, not Uint8List → cast<int>() crashed.
    // After the fix, every byte must round-trip exactly.
    expect(row.ciphertext, equals(bytes.ciphertext),
        reason: 'bytea decode regression — see decodeBytea in supabase_sync_server.dart');
    expect(row.aadHash, equals(bytes.aadHash));
  }, timeout: const Timeout(Duration(seconds: 30)));
}
