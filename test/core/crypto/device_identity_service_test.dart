import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dreambook/core/crypto/device_identity_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_fakes/in_memory_secure_storage.dart';

void main() {
  late InMemorySecureStorage storage;
  late DeviceIdentityService service;

  setUp(() {
    storage = InMemorySecureStorage();
    service = DeviceIdentityService.forTest(storage);
  });

  group('DeviceIdentityService', () {
    test('getOrCreate() generates new keypair on first call and persists', () async {
      final id1 = await service.getOrCreate();
      expect(id1.publicKeyBytes.length, 32);
      final id2 = await service.getOrCreate();
      expect(id2.publicKeyBytes, id1.publicKeyBytes,
          reason: 'second call must return same persisted keypair');
    });

    test('signature is verifiable with the returned public key', () async {
      final id = await service.getOrCreate();
      final message = utf8.encode('hello world');
      final sig = await service.sign(message);
      final algo = Ed25519();
      final pubKey = SimplePublicKey(id.publicKeyBytes, type: KeyPairType.ed25519);
      final ok = await algo.verify(
        message,
        signature: Signature(sig, publicKey: pubKey),
      );
      expect(ok, isTrue);
    });

    test('public key round-trips through base64Url encoding', () async {
      final id = await service.getOrCreate();
      final encoded = base64Url.encode(id.publicKeyBytes);
      final decoded = base64Url.decode(encoded);
      expect(Uint8List.fromList(decoded), id.publicKeyBytes);
    });
  });
}
