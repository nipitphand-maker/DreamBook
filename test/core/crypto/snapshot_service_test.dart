import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dreambook/core/crypto/snapshot_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final testKdf =
      Argon2id(memory: 256, parallelism: 1, iterations: 1, hashLength: 32);

  SnapshotService makeService() => SnapshotService(kdf: testKdf);

  final rng = Random.secure();
  Uint8List randBytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => rng.nextInt(256)));

  group('SnapshotService', () {
    test('round-trip: prepare then restore recovers K_family and rows',
        () async {
      final svc = makeService();
      final familyKey = randBytes(32);
      const familyId = 'fam-abc-123';
      const keyVersion = 1;
      const snapshotVersion = 1;
      const passphrase = 'correct-horse-battery-staple-phrase';

      final rows = [
        {
          'table_name': 'feed',
          'record_id': 'r1',
          'version': 1,
          'key_version': keyVersion,
          'family_id': familyId,
          'ciphertext': base64.encode(randBytes(64)),
          'aad_hash': base64.encode(randBytes(32)),
          'written_by_device': 'dev1',
          'updated_at': '2026-05-01T00:00:00.000Z',
          'deleted_at': null,
        },
      ];

      final prepared = await svc.prepare(
        passphrase: passphrase,
        familyKey: familyKey,
        familyId: familyId,
        keyVersion: keyVersion,
        snapshotVersion: snapshotVersion,
        rows: rows,
      );

      expect(prepared.salt.length, 16);
      expect(prepared.wrappedKey.isNotEmpty, true);
      expect(prepared.encryptedPayload.isNotEmpty, true);
      expect(prepared.payloadHash.length, 32);

      final restored = await svc.restore(
        passphrase: passphrase,
        encryptedPayload: prepared.encryptedPayload,
        wrappedKey: prepared.wrappedKey,
        salt: prepared.salt,
        familyId: familyId,
        keyVersion: keyVersion,
        snapshotVersion: snapshotVersion,
      );

      expect(restored.familyKey, equals(familyKey));
      expect(restored.rows.length, 1);
      expect(restored.rows[0]['table_name'], 'feed');
      expect(restored.rows[0]['record_id'], 'r1');
    });

    test('wrong passphrase throws SecretBoxAuthenticationError', () async {
      final svc = makeService();
      final familyKey = randBytes(32);
      const familyId = 'fam-xyz';
      const keyVersion = 2;
      const snapshotVersion = 3;

      final prepared = await svc.prepare(
        passphrase: 'correct-passphrase',
        familyKey: familyKey,
        familyId: familyId,
        keyVersion: keyVersion,
        snapshotVersion: snapshotVersion,
        rows: [],
      );

      await expectLater(
        svc.restore(
          passphrase: 'wrong-passphrase',
          encryptedPayload: prepared.encryptedPayload,
          wrappedKey: prepared.wrappedKey,
          salt: prepared.salt,
          familyId: familyId,
          keyVersion: keyVersion,
          snapshotVersion: snapshotVersion,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('payloadHash is SHA-256 of encryptedPayload', () async {
      final svc = makeService();
      final prepared = await svc.prepare(
        passphrase: 'pass',
        familyKey: randBytes(32),
        familyId: 'fam-1',
        keyVersion: 1,
        snapshotVersion: 1,
        rows: [],
      );

      final recomputed = await Sha256().hash(prepared.encryptedPayload);
      expect(prepared.payloadHash,
          equals(Uint8List.fromList(recomputed.bytes)));
    });

    test('two prepares with same params produce different ciphertext',
        () async {
      final svc = makeService();
      final familyKey = randBytes(32);

      final a = await svc.prepare(
        passphrase: 'pass',
        familyKey: familyKey,
        familyId: 'fam',
        keyVersion: 1,
        snapshotVersion: 1,
        rows: [],
      );
      final b = await svc.prepare(
        passphrase: 'pass',
        familyKey: familyKey,
        familyId: 'fam',
        keyVersion: 1,
        snapshotVersion: 1,
        rows: [],
      );

      expect(a.salt, isNot(equals(b.salt)));
      expect(a.encryptedPayload, isNot(equals(b.encryptedPayload)));
    });
  });
}
