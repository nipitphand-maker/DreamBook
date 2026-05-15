// ignore_for_file: lines_longer_than_80_chars
@Tags(['security'])

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../_fakes/fake_supabase_server.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Invite reuse (SEC-4)', () {
    test('SEC-4: second claim of same invite code is rejected', () async {
      final server = FakeSupabaseServer();
      server.families['fam-x'] =
          FakeFamily(id: 'fam-x', currentKeyVersion: 1);
      server.devices['dev-x'] = FakeDevice(
        deviceFp: 'dev-x',
        familyId: 'fam-x',
        devicePubKey: Uint8List(32),
        role: 'admin',
        keyVersionAtJoin: 1,
      );

      // Seed an invite in the fake server (keyed by codeHash).
      server.invites['hash-abc'] = FakeInvite(
        codeHash: 'hash-abc',
        familyId: 'fam-x',
        salt: Uint8List(16),
        wrappedKey: Uint8List(32),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      // First claim — should succeed and mark the invite as consumed.
      await server.claimInvite(
        codeHash: 'hash-abc',
        deviceFp: 'dev-y',
        devicePubKey: Uint8List(32),
      );

      // Verify first claim consumed the invite.
      final invite = server.invites['hash-abc']!;
      expect(invite.consumedAt, isNotNull);
      expect(invite.claimDeviceFp, 'dev-y');

      // Second claim attempt — claimInvite should throw (invite already consumed).
      await expectLater(
        () => server.claimInvite(
          codeHash: 'hash-abc',
          deviceFp: 'dev-z',
          devicePubKey: Uint8List(32),
        ),
        throwsA(isA<FakeHttpException>()),
        reason: 'SEC-4: invite marked consumed prevents replay',
      );
    });
  });
}
