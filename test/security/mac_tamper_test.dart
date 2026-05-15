// ignore_for_file: lines_longer_than_80_chars
@Tags(['security'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dreambook/core/crypto/crypto_envelope.dart';
import 'package:dreambook/core/sync/sync_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SecretKey key;
  late CryptoEnvelope envelope;

  setUp(() async {
    key = await AesGcm.with256bits().newSecretKey();
    envelope = CryptoEnvelope();
  });

  group('MAC tamper detection (SEC-6, SEC-7, SEC-8)', () {
    // SEC-6: Ciphertext tamper → MAC fails
    test('SEC-6: ciphertext tamper detected by MAC', () async {
      final plaintext = utf8.encode('sensitive feed entry 4oz left');
      final aad = utf8.encode('feed|r1|1|fam-a|1');
      final ct = await envelope.seal(plaintext, key, aad);

      // Flip a byte in the ciphertext area (offset 1=version, 1–12=nonce,
      // 13+ = ciphertext; index 13 is safely within the ciphertext portion).
      final tampered = Uint8List.fromList(ct);
      tampered[13] ^= 0xFF;

      await expectLater(
        () => envelope.open(tampered, key, aad),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    // SEC-7: AAD swap → MAC fails
    test('SEC-7: family_id swap in AAD detected by MAC', () async {
      final plaintext = utf8.encode('sensitive entry');
      final aad = utf8.encode('feed|r1|1|fam-a|1');
      final ct = await envelope.seal(plaintext, key, aad);

      final swappedAad =
          utf8.encode('feed|r1|1|fam-b|1'); // different family_id
      await expectLater(
        () => envelope.open(ct, key, swappedAad),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    // SEC-8: Cross-family snapshot restore — same as AAD swap
    // since snapshots use family_id in AAD.
    test('SEC-8: cross-family snapshot restore rejected on AAD family_id',
        () async {
      final snapshotPlaintext = utf8.encode('snapshot payload for fam-a');
      final aad = utf8.encode('snapshot|snap-001|1|fam-a|1');
      final ct = await envelope.seal(snapshotPlaintext, key, aad);

      // Attempt restore with fam-b's AAD — MAC must fail.
      final wrongFamilyAad = utf8.encode('snapshot|snap-001|1|fam-b|1');
      await expectLater(
        () => envelope.open(ct, key, wrongFamilyAad),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    // SEC-9: SyncRlsReject carries a descriptive message
    test('SEC-9: SyncRlsReject message is descriptive (not empty)', () {
      const e = SyncRlsReject('No K_family in storage for this family');
      expect(e.message, isNotEmpty);
    });
  });
}
