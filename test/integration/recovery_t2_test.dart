// @Tags(['integration'])
// Tests the full BIP-39 → Argon2id → AES-GCM → recovery round-trip.
// Uses low-memory Argon2id params so CI finishes in <30s.

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dreambook/core/crypto/bip39_service.dart';
import 'package:dreambook/core/crypto/recovery_service.dart';

void main() {
  final testKdf = Argon2id(memory: 256, parallelism: 1, iterations: 1, hashLength: 32);

  final bip39 = Bip39Service();
  RecoveryService makeRecovery() => RecoveryService(kdf: testKdf);

  group('T2 recovery round-trip', () {
    test('generate → validate → wrap → unwrap recovers K_family', () async {
      final phrase = bip39.generatePhrase();
      expect(bip39.validatePhrase(phrase), isTrue);

      final familyKey = Uint8List.fromList(List.generate(32, (i) => i ^ 0xAB));
      const familyId = 'integration-test-family';
      const keyVersion = 1;

      final recovery = makeRecovery();
      final normalized = bip39.normalizePhrase(phrase);

      final wrapped = await recovery.wrapFamilyKey(
        normalizedPhrase: normalized,
        familyKey: familyKey,
        familyId: familyId,
        keyVersion: keyVersion,
      );

      expect(wrapped.wrappedKey.isNotEmpty, isTrue);
      expect(wrapped.salt.length, 16);

      final recovered = await recovery.unwrapFamilyKey(
        normalizedPhrase: normalized,
        wrappedKey: wrapped.wrappedKey,
        salt: wrapped.salt,
        familyId: familyId,
        keyVersion: keyVersion,
      );

      expect(recovered, equals(familyKey));
    });

    test('lookup hash is deterministic after normalisation', () async {
      const rawPhrase =
          '  ABANDON  ABILITY  ABLE  ABOUT  ABOVE  ABSENT  ABSORB  ABSTRACT  ABSURD  ABUSE  ACCESS  ACCIDENT  ';
      final h1 = await bip39.lookupHash(rawPhrase);
      final h2 = await bip39.lookupHash(
        'abandon ability able about above absent absorb abstract absurd abuse access accident',
      );
      expect(h1, equals(h2));
    });

    test('wrong phrase fails unwrap', () async {
      final phrase = bip39.generatePhrase();
      final differentPhrase = bip39.generatePhrase();
      final familyKey = Uint8List.fromList(List.generate(32, (i) => i));

      final recovery = makeRecovery();
      final wrapped = await recovery.wrapFamilyKey(
        normalizedPhrase: bip39.normalizePhrase(phrase),
        familyKey: familyKey,
        familyId: 'fid',
        keyVersion: 1,
      );

      await expectLater(
        () => recovery.unwrapFamilyKey(
          normalizedPhrase: bip39.normalizePhrase(differentPhrase),
          wrappedKey: wrapped.wrappedKey,
          salt: wrapped.salt,
          familyId: 'fid',
          keyVersion: 1,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('rate-limit simulation: 5 wrong phrases throw, correct phrase succeeds', () async {
      final realPhrase = bip39.generatePhrase();
      final recovery = makeRecovery();
      final familyKey = Uint8List.fromList(List.generate(32, (i) => i * 2));
      final normalized = bip39.normalizePhrase(realPhrase);

      final wrapped = await recovery.wrapFamilyKey(
        normalizedPhrase: normalized,
        familyKey: familyKey,
        familyId: 'fid',
        keyVersion: 2,
      );

      for (var i = 0; i < 4; i++) {
        final wrong = bip39.generatePhrase();
        await expectLater(
          () => recovery.unwrapFamilyKey(
            normalizedPhrase: bip39.normalizePhrase(wrong),
            wrappedKey: wrapped.wrappedKey,
            salt: wrapped.salt,
            familyId: 'fid',
            keyVersion: 2,
          ),
          throwsA(isA<SecretBoxAuthenticationError>()),
        );
      }

      final result = await recovery.unwrapFamilyKey(
        normalizedPhrase: normalized,
        wrappedKey: wrapped.wrappedKey,
        salt: wrapped.salt,
        familyId: 'fid',
        keyVersion: 2,
      );
      expect(result, equals(familyKey));
    });
  });
}
