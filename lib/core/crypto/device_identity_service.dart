import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Device-level identity. One Ed25519 keypair per install, persisted in
/// secure storage. The public key is the device fingerprint sent to
/// Supabase at handshake (per spec §6.4 / auditor #1 recommendation).
class DeviceIdentity {
  const DeviceIdentity({required this.publicKeyBytes});
  final Uint8List publicKeyBytes;

  /// Stable device fingerprint. Matches the formula used by
  /// `supabase/functions/bootstrap_family/index.ts` (SHA-256 of the
  /// device public key, first 16 bytes, lowercase hex). Used as
  /// `written_by_device` on encrypted_rows pushes — must equal
  /// `encode(family_devices.device_fp, 'hex')` for RLS to accept the
  /// write (see `supabase/migrations/0017_rls_reharden.sql`).
  Future<String> fingerprintHex() async {
    final hash = await Sha256().hash(publicKeyBytes);
    return hash.bytes
        .sublist(0, 16)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}

class DeviceIdentityService {
  DeviceIdentityService(this._storage);
  DeviceIdentityService.forTest(dynamic storage) : _storage = storage;

  /// Combined JSON entry key — stores both pub + priv in a single atomic write.
  /// Legacy split-key aliases are kept only for orphan-cleanup detection below.
  static const String _combinedAlias = 'dreambook_device_keypair_v1';
  static const String _legacyPrivAlias = 'dreambook_device_priv_v1';
  static const String _legacyPubAlias = 'dreambook_device_pub_v1';

  final dynamic _storage;
  final Ed25519 _algo = Ed25519();

  Future<DeviceIdentity> getOrCreate() async {
    // --- Startup check: detect orphaned half-written legacy entries ----------
    // If the combined entry is absent but a legacy half exists, the previous
    // write was interrupted between the two separate writes (RISK-2).
    // Delete the orphan and regenerate cleanly.
    final combined = await _storage.read(key: _combinedAlias) as String?;
    if (combined == null) {
      final legacyPub = await _storage.read(key: _legacyPubAlias) as String?;
      final legacyPriv = await _storage.read(key: _legacyPrivAlias) as String?;
      if (legacyPub != null || legacyPriv != null) {
        // Orphaned half — delete both halves and fall through to regenerate.
        await _storage.delete(key: _legacyPubAlias);
        await _storage.delete(key: _legacyPrivAlias);
      }
    }

    // --- Fast path: combined entry already exists ----------------------------
    if (combined != null) {
      final map = jsonDecode(combined) as Map<String, dynamic>;
      return DeviceIdentity(
        publicKeyBytes:
            Uint8List.fromList(base64Url.decode(map['pub'] as String)),
      );
    }

    // --- First run: generate keypair and write atomically --------------------
    final pair = await _algo.newKeyPair();
    final pub = await pair.extractPublicKey();
    final priv = await pair.extractPrivateKeyBytes();
    // Single write — eliminates the torn-write window between two separate
    // write() calls that existed in the prior split-alias implementation.
    await _storage.write(
      key: _combinedAlias,
      value: jsonEncode({
        'pub': base64Url.encode(pub.bytes),
        'priv': base64Url.encode(priv),
      }),
    );
    return DeviceIdentity(publicKeyBytes: Uint8List.fromList(pub.bytes));
  }

  Future<List<int>> sign(List<int> message) async {
    final combined = await _storage.read(key: _combinedAlias) as String?;
    if (combined == null) {
      throw StateError('Device identity not initialised — call getOrCreate first');
    }
    final map = jsonDecode(combined) as Map<String, dynamic>;
    final priv = base64Url.decode(map['priv'] as String);
    final pair = await _algo.newKeyPairFromSeed(priv);
    final sig = await _algo.sign(message, keyPair: pair);
    return sig.bytes;
  }
}
