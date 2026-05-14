import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../crypto/crypto_envelope.dart';
import '../crypto/family_key_service.dart';
import 'sync_server.dart';

typedef AdminPublicKeyResolver = Future<PublicKey> Function(String deviceFp);

/// Receives wrapped-key envelopes from `key_distribution` after a rotation
/// and installs the new K_family locally. The wrap uses X25519 shared
/// secret between admin's private key and our public key.
class KeyDistributionService {
  KeyDistributionService({
    required this.server,
    required this.familyKeys,
    required this.ourPrivateKeyPair,
    required this.adminPublicKeyResolver,
    CryptoEnvelope? envelope,
  }) : _envelope = envelope ?? CryptoEnvelope();

  final SyncServer server;
  final FamilyKeyService familyKeys;
  final SimpleKeyPair ourPrivateKeyPair;
  final AdminPublicKeyResolver adminPublicKeyResolver;
  final CryptoEnvelope _envelope;
  final X25519 _x25519 = X25519();

  /// Look for a `key_distribution` row addressed to this device with a
  /// `key_version` higher than what we currently hold. If found, derive
  /// the shared secret, unwrap, install as new K_family. Returns true on
  /// success, false when nothing newer is available.
  Future<bool> fetchAndStoreLatest({
    required String familyId,
    required String deviceFp,
  }) async {
    final current = await familyKeys.read(familyId: familyId);
    final currentVer = current?.keyVersion ?? 0;
    final rows = await server.pullKeyDistribution(recipientDeviceFp: deviceFp);
    final filtered = rows.where((r) => r.familyId == familyId).toList()
      ..sort((a, b) => b.keyVersion.compareTo(a.keyVersion));
    if (filtered.isEmpty || filtered.first.keyVersion <= currentVer) {
      return false;
    }
    final newest = filtered.first;
    final adminPub = await adminPublicKeyResolver(deviceFp);
    final shared = await _x25519.sharedSecretKey(
      keyPair: ourPrivateKeyPair,
      remotePublicKey: adminPub,
    );
    final plaintext = await _envelope.open(
      newest.wrappedKey,
      shared,
      utf8.encode('$familyId|${newest.keyVersion}'),
    );
    await familyKeys.install(
      familyId: familyId,
      bytes: plaintext,
      keyVersion: newest.keyVersion,
    );
    return true;
  }
}
