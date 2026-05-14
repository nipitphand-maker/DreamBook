import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dreambook/core/crypto/crypto_envelope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SecretKey key;
  late CryptoEnvelope envelope;

  setUp(() async {
    key = await AesGcm.with256bits().newSecretKey();
    envelope = CryptoEnvelope();
  });

  group('CryptoEnvelope', () {
    test('seal then open round-trips plaintext', () async {
      final plaintext = utf8.encode('feed at 14:25, 4oz, left breast');
      final aad = utf8.encode('feed|abc123|3|fam-001|1');
      final ct = await envelope.seal(plaintext, key, aad);
      final back = await envelope.open(ct, key, aad);
      expect(back, plaintext);
    });

    test('open rejects ciphertext with tampered AAD', () async {
      final plaintext = utf8.encode('hello');
      final aad = utf8.encode('feed|id|1|fam|1');
      final ct = await envelope.seal(plaintext, key, aad);
      final tamperedAad = utf8.encode('feed|id|2|fam|1'); // version bumped
      expect(
        () => envelope.open(ct, key, tamperedAad),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('open rejects ciphertext under a different key', () async {
      final plaintext = utf8.encode('hello');
      final aad = utf8.encode('feed|id|1|fam|1');
      final ct = await envelope.seal(plaintext, key, aad);
      final otherKey = await AesGcm.with256bits().newSecretKey();
      expect(
        () => envelope.open(ct, otherKey, aad),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('seal produces unique nonces across 10k seals (probabilistic)', () async {
      final plaintext = utf8.encode('x');
      final aad = utf8.encode('a');
      final seen = <String>{};
      for (var i = 0; i < 10000; i++) {
        final ct = await envelope.seal(plaintext, key, aad);
        final nonce = base64Encode(ct.sublist(0, 12));
        expect(seen.add(nonce), isTrue,
            reason: 'nonce collision at iteration $i');
      }
    });

    test('envelope layout: 12-byte nonce prefix + ciphertext + 16-byte mac', () async {
      final plaintext = Uint8List.fromList(List.filled(100, 0x42));
      final aad = utf8.encode('a');
      final ct = await envelope.seal(plaintext, key, aad);
      // 12 (nonce) + 100 (ct same length as plaintext for GCM) + 16 (mac) = 128
      expect(ct.length, 12 + 100 + 16);
    });
  });
}
