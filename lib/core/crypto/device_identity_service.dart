import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Device-level identity. One Ed25519 keypair per install, persisted in
/// secure storage. The public key is the device fingerprint sent to
/// Supabase at handshake (per spec §6.4 / auditor #1 recommendation).
class DeviceIdentity {
  const DeviceIdentity({required this.publicKeyBytes});
  final Uint8List publicKeyBytes;
}

class DeviceIdentityService {
  DeviceIdentityService(this._storage);
  DeviceIdentityService.forTest(dynamic storage) : _storage = storage;

  static const String _privKeyAlias = 'dreambook_device_priv_v1';
  static const String _pubKeyAlias = 'dreambook_device_pub_v1';

  final dynamic _storage;
  final Ed25519 _algo = Ed25519();

  Future<DeviceIdentity> getOrCreate() async {
    final existingPub = await _storage.read(key: _pubKeyAlias) as String?;
    if (existingPub != null) {
      return DeviceIdentity(
        publicKeyBytes: Uint8List.fromList(base64Url.decode(existingPub)),
      );
    }
    final pair = await _algo.newKeyPair();
    final pub = await pair.extractPublicKey();
    final priv = await pair.extractPrivateKeyBytes();
    await _storage.write(
      key: _privKeyAlias,
      value: base64Url.encode(priv),
    );
    await _storage.write(
      key: _pubKeyAlias,
      value: base64Url.encode(pub.bytes),
    );
    return DeviceIdentity(publicKeyBytes: Uint8List.fromList(pub.bytes));
  }

  Future<List<int>> sign(List<int> message) async {
    final privRaw = await _storage.read(key: _privKeyAlias) as String?;
    if (privRaw == null) {
      throw StateError('Device identity not initialised — call getOrCreate first');
    }
    final priv = base64Url.decode(privRaw);
    final pair = await _algo.newKeyPairFromSeed(priv);
    final sig = await _algo.sign(message, keyPair: pair);
    return sig.bytes;
  }
}
