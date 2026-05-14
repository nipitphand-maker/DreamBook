import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dreambook/core/crypto/crypto_envelope.dart';
import 'package:dreambook/core/crypto/family_key_service.dart';
import 'package:dreambook/core/sync/key_distribution_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_fakes/fake_supabase_server.dart';
import '../../_fakes/in_memory_secure_storage.dart';

void main() {
  late FakeSupabaseServer server;
  late FamilyKeyService familyKeys;
  late KeyDistributionService service;
  const familyId = 'fam-1';
  const ourDeviceFp = 'device-pub';

  setUp(() async {
    server = FakeSupabaseServer();
    server.families[familyId] = FakeFamily(id: familyId, currentKeyVersion: 1);
    familyKeys = FamilyKeyService.forTest(InMemorySecureStorage());
    await familyKeys.generate(familyId: familyId, keyVersion: 1);
  });

  tearDown(() => server.dispose());

  group('KeyDistributionService', () {
    test('fetchAndStoreLatest() unwraps a newer key_version envelope via X25519', () async {
      final x = X25519();
      final adminPair = await x.newKeyPair();
      final ourPair = await x.newKeyPair();
      final ourPub = await ourPair.extractPublicKey();
      final newKey = List<int>.generate(32, (i) => i * 2);
      final shared = await x.sharedSecretKey(
        keyPair: adminPair,
        remotePublicKey: ourPub,
      );
      final wrapped = await CryptoEnvelope().seal(
        newKey,
        shared,
        utf8.encode('$familyId|2'),
      );

      server.keyDistribution.add(
        FakeKeyDistributionRow(
          familyId: familyId,
          recipientDeviceFp: ourDeviceFp,
          keyVersion: 2,
          wrappedKey: wrapped,
        ),
      );
      server.families[familyId]!.currentKeyVersion = 2;

      service = KeyDistributionService(
        server: server,
        familyKeys: familyKeys,
        ourPrivateKeyPair: ourPair,
        adminPublicKeyResolver: (_) async => await adminPair.extractPublicKey(),
      );
      final ok = await service.fetchAndStoreLatest(
        familyId: familyId,
        deviceFp: ourDeviceFp,
      );
      expect(ok, isTrue);
      final stored = await familyKeys.read(familyId: familyId);
      expect(stored!.keyVersion, 2);
      expect(stored.bytes, Uint8List.fromList(newKey));
    });

    test('returns false when no newer key_version is available', () async {
      service = KeyDistributionService(
        server: server,
        familyKeys: familyKeys,
        ourPrivateKeyPair: await X25519().newKeyPair(),
        adminPublicKeyResolver: (_) async =>
            SimplePublicKey(const [], type: KeyPairType.x25519),
      );
      final ok = await service.fetchAndStoreLatest(
        familyId: familyId,
        deviceFp: ourDeviceFp,
      );
      expect(ok, isFalse);
    });

    test('refuses to install older key_version than what we have', () async {
      await familyKeys.rotate(familyId: familyId); // now at v2
      server.keyDistribution.add(
        FakeKeyDistributionRow(
          familyId: familyId,
          recipientDeviceFp: ourDeviceFp,
          keyVersion: 1,
          wrappedKey: Uint8List(48),
        ),
      );
      service = KeyDistributionService(
        server: server,
        familyKeys: familyKeys,
        ourPrivateKeyPair: await X25519().newKeyPair(),
        adminPublicKeyResolver: (_) async =>
            SimplePublicKey(const [], type: KeyPairType.x25519),
      );
      final ok = await service.fetchAndStoreLatest(
        familyId: familyId,
        deviceFp: ourDeviceFp,
      );
      expect(ok, isFalse);
    });
  });
}
