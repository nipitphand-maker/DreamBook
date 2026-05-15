// @Tags(['integration'])
// Tests the full T3 snapshot crypto round-trip (SnapshotService only — no Supabase).
// Uses low-memory Argon2id params so CI finishes in <10s.

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dreambook/core/crypto/snapshot_service.dart';

void main() {
  final testKdf = Argon2id(memory: 256, parallelism: 1, iterations: 1, hashLength: 32);

  SnapshotService makeService() => SnapshotService(kdf: testKdf);

  group('T3 snapshot crypto round-trip', () {
    test('round-trip recovers familyKey and rows', () async {
      final familyKey = Uint8List.fromList(List.generate(32, (i) => i ^ 0xCD));
      const passphrase = 'correct-horse-battery-staple';
      const familyId = 'integration-test-family-t3';
      const keyVersion = 1;
      const snapshotVersion = 0;

      final rows = [
        {'record_id': 'row-001', 'type': 'feed', 'amount_ml': 120},
        {'record_id': 'row-002', 'type': 'diaper', 'note': 'wet'},
      ];

      final service = makeService();

      final prepared = await service.prepare(
        passphrase: passphrase,
        familyKey: familyKey,
        familyId: familyId,
        keyVersion: keyVersion,
        snapshotVersion: snapshotVersion,
        rows: rows,
      );

      expect(prepared.encryptedPayload.isNotEmpty, isTrue);
      expect(prepared.wrappedKey.isNotEmpty, isTrue);
      expect(prepared.salt.length, 16);
      expect(prepared.payloadHash.length, 32);

      final restored = await service.restore(
        passphrase: passphrase,
        encryptedPayload: prepared.encryptedPayload,
        wrappedKey: prepared.wrappedKey,
        salt: prepared.salt,
        familyId: familyId,
        keyVersion: keyVersion,
        snapshotVersion: snapshotVersion,
      );

      expect(restored.familyKey, equals(familyKey));
      expect(restored.rows[0]['record_id'], equals('row-001'));
    });

    test('wrong passphrase throws SecretBoxAuthenticationError', () async {
      final familyKey = Uint8List.fromList(List.generate(32, (i) => i));
      const passphrase = 'correct-passphrase';
      const familyId = 'fid-t3-wrong-pass';
      const keyVersion = 1;
      const snapshotVersion = 0;

      final service = makeService();

      final prepared = await service.prepare(
        passphrase: passphrase,
        familyKey: familyKey,
        familyId: familyId,
        keyVersion: keyVersion,
        snapshotVersion: snapshotVersion,
        rows: [
          {'record_id': 'r1'},
        ],
      );

      await expectLater(
        () => service.restore(
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

    test('tampered encryptedPayload throws SecretBoxAuthenticationError', () async {
      final familyKey = Uint8List.fromList(List.generate(32, (i) => i * 3));
      const passphrase = 'tamper-test-passphrase';
      const familyId = 'fid-t3-tamper';
      const keyVersion = 1;
      const snapshotVersion = 0;

      final service = makeService();

      final prepared = await service.prepare(
        passphrase: passphrase,
        familyKey: familyKey,
        familyId: familyId,
        keyVersion: keyVersion,
        snapshotVersion: snapshotVersion,
        rows: [
          {'record_id': 'r-tamper'},
        ],
      );

      // Flip one byte in the ciphertext body (past the version byte at [0]
      // and the 12-byte nonce) to simulate tampering without touching the
      // version byte (which causes a FormatException before MAC verification).
      final tampered = Uint8List.fromList(prepared.encryptedPayload);
      // Layout: version(1) || nonce(12) || ciphertext(N) || mac(16)
      // Byte at index 13 is the first byte of the ciphertext body.
      tampered[13] ^= 0xFF;

      await expectLater(
        () => service.restore(
          passphrase: passphrase,
          encryptedPayload: tampered,
          wrappedKey: prepared.wrappedKey,
          salt: prepared.salt,
          familyId: familyId,
          keyVersion: keyVersion,
          snapshotVersion: snapshotVersion,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });
}
