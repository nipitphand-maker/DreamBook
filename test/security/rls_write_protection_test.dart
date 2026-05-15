// ignore_for_file: lines_longer_than_80_chars
@Tags(['security'])
library;

import 'dart:typed_data';

import 'package:dreambook/core/sync/sync_error.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_fakes/fake_supabase_server.dart';

void main() {
  group('RLS write protection (SEC-1, SEC-2, SEC-3)', () {
    late FakeSupabaseServer server;

    setUp(() {
      server = FakeSupabaseServer();
      // Seed a family and an admin device.
      server.families['fam-a'] = FakeFamily(id: 'fam-a', currentKeyVersion: 1);
      server.devices['dev-a'] = FakeDevice(
        deviceFp: 'dev-a',
        familyId: 'fam-a',
        devicePubKey: Uint8List(32),
        role: 'admin',
        keyVersionAtJoin: 1,
      );
    });

    // SEC-1: Spoofed written_by_device rejected
    test('SEC-1: spoofed written_by_device is rejected', () async {
      await expectLater(
        () => server.insertEncryptedRow(
          id: 'r1',
          familyId: 'fam-a',
          tableName: 'feed',
          recordId: 'r1',
          version: 1,
          keyVersion: 1,
          ciphertext: Uint8List(1),
          aadHash: Uint8List(1),
          writtenByDevice: 'evil-device', // NOT a device in the family
          updatedAt: DateTime.now(),
        ),
        throwsA(isA<SyncRlsReject>()),
      );
    });

    // SEC-2: Stale key_version rejected
    test('SEC-2: stale key_version insert rejected', () async {
      // Bump key version on the family.
      server.families['fam-a']!.currentKeyVersion = 2;
      await expectLater(
        () => server.insertEncryptedRow(
          id: 'r2',
          familyId: 'fam-a',
          tableName: 'feed',
          recordId: 'r2',
          version: 1,
          keyVersion: 1, // stale — family is now v2
          ciphertext: Uint8List(1),
          aadHash: Uint8List(1),
          writtenByDevice: 'dev-a',
          updatedAt: DateTime.now(),
        ),
        throwsA(isA<SyncRlsReject>()),
      );
    });

    // SEC-3a: Cross-family SELECT blocked — pullRows for wrong family returns empty
    test("SEC-3a: cross-family pull returns empty (not someone else's data)",
        () async {
      // Insert row for fam-a.
      await server.insertEncryptedRow(
        id: 'r3',
        familyId: 'fam-a',
        tableName: 'feed',
        recordId: 'r3',
        version: 1,
        keyVersion: 1,
        ciphertext: Uint8List(1),
        aadHash: Uint8List(1),
        writtenByDevice: 'dev-a',
        updatedAt: DateTime.now(),
      );
      // Pull for a different family — should be empty.
      final rows = await server.pullRows(familyId: 'fam-b');
      expect(rows, isEmpty);
    });

    // SEC-3b: Cross-family INSERT blocked
    test('SEC-3b: cross-family insert blocked', () async {
      // dev-a is in fam-a, not fam-b.
      await expectLater(
        () => server.insertEncryptedRow(
          id: 'r4',
          familyId: 'fam-b',
          tableName: 'feed',
          recordId: 'r4',
          version: 1,
          keyVersion: 1,
          ciphertext: Uint8List(1),
          aadHash: Uint8List(1),
          writtenByDevice: 'dev-a', // dev-a is not in fam-b
          updatedAt: DateTime.now(),
        ),
        throwsA(isA<SyncRlsReject>()),
      );
    });

    // SEC-3c: Cross-family UPDATE blocked — same as INSERT for our fake
    test('SEC-3c: cross-family overwrite attempt blocked', () async {
      // Try to insert a row with fam-b family_id using dev-a credentials.
      await expectLater(
        () => server.insertEncryptedRow(
          id: 'r5',
          familyId: 'fam-b',
          tableName: 'feed',
          recordId: 'r5',
          version: 2,
          keyVersion: 1,
          ciphertext: Uint8List(1),
          aadHash: Uint8List(1),
          writtenByDevice: 'dev-a',
          updatedAt: DateTime.now(),
        ),
        throwsA(isA<SyncRlsReject>()),
      );
    });
  });
}
