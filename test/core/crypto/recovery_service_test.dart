import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dreambook/core/crypto/recovery_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Use low-memory Argon2id for tests — production uses m=64MiB which is slow.
  final testKdf = Argon2id(memory: 256, parallelism: 1, iterations: 1, hashLength: 32);

  late RecoveryService service;
  setUp(() => service = RecoveryService(kdf: testKdf));

  group('wrapFamilyKey / unwrapFamilyKey', () {
    test('round-trip recovers original K_family', () async {
      const phrase = 'abandon ability able about above absent absorb abstract absurd abuse access accident';
      final familyKey = Uint8List.fromList(List.generate(32, (i) => i));
      const familyId = 'test-family-id';
      const keyVersion = 1;

      final wrapped = await service.wrapFamilyKey(
        normalizedPhrase: phrase,
        familyKey: familyKey,
        familyId: familyId,
        keyVersion: keyVersion,
      );

      expect(wrapped.salt.length, 16);
      expect(wrapped.wrappedKey.isNotEmpty, isTrue);

      final recovered = await service.unwrapFamilyKey(
        normalizedPhrase: phrase,
        wrappedKey: wrapped.wrappedKey,
        salt: wrapped.salt,
        familyId: familyId,
        keyVersion: keyVersion,
      );

      expect(recovered, equals(familyKey));
    });

    test('wrong phrase throws SecretBoxAuthenticationError', () async {
      const rightPhrase = 'abandon ability able about above absent absorb abstract absurd abuse access accident';
      const wrongPhrase = 'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong';
      final familyKey = Uint8List.fromList(List.generate(32, (i) => i + 1));

      final wrapped = await service.wrapFamilyKey(
        normalizedPhrase: rightPhrase,
        familyKey: familyKey,
        familyId: 'fid',
        keyVersion: 1,
      );

      await expectLater(
        () => service.unwrapFamilyKey(
          normalizedPhrase: wrongPhrase,
          wrappedKey: wrapped.wrappedKey,
          salt: wrapped.salt,
          familyId: 'fid',
          keyVersion: 1,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('wrong familyId throws SecretBoxAuthenticationError', () async {
      const phrase = 'abandon ability able about above absent absorb abstract absurd abuse access accident';
      final familyKey = Uint8List.fromList(List.generate(32, (i) => i));

      final wrapped = await service.wrapFamilyKey(
        normalizedPhrase: phrase,
        familyKey: familyKey,
        familyId: 'family-a',
        keyVersion: 1,
      );

      await expectLater(
        () => service.unwrapFamilyKey(
          normalizedPhrase: phrase,
          wrappedKey: wrapped.wrappedKey,
          salt: wrapped.salt,
          familyId: 'family-b',
          keyVersion: 1,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('each wrap produces different salt and ciphertext', () async {
      const phrase = 'abandon ability able about above absent absorb abstract absurd abuse access accident';
      final familyKey = Uint8List.fromList(List.generate(32, (i) => i));

      final w1 = await service.wrapFamilyKey(
        normalizedPhrase: phrase,
        familyKey: familyKey,
        familyId: 'fid',
        keyVersion: 1,
      );
      final w2 = await service.wrapFamilyKey(
        normalizedPhrase: phrase,
        familyKey: familyKey,
        familyId: 'fid',
        keyVersion: 1,
      );

      expect(w1.salt, isNot(equals(w2.salt)));
      expect(w1.wrappedKey, isNot(equals(w2.wrappedKey)));
    });
  });
}
