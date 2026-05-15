import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'crockford_base32.dart';
import 'crypto_envelope.dart';

/// Output of wrap step — the two values the server needs to store in
/// the `invites` table (alongside family_id, expiry, etc.).
class WrappedFamilyKey {
  const WrappedFamilyKey({required this.salt, required this.wrappedKeyEnvelope});

  final Uint8List salt; // 16 bytes
  final Uint8List wrappedKeyEnvelope; // CryptoEnvelope output
}

/// Per spec §3.1 / §5.2:
/// - code = Crockford base32 of 40 random bits → "XXXX-XXXX"
/// - hash for server = BLAKE2b(normalised(code))
/// - KDF = Argon2id m=64 MiB, t=3, p=1, len=32
/// - wrap = AES-GCM(K_kdf, K_family, aad=family_id)
class InviteCodeService {
  InviteCodeService({
    Argon2id? kdf,
    CryptoEnvelope? envelope,
    Random? rng,
  })  : _kdf = kdf ?? _defaultKdf(),
        _envelope = envelope ?? CryptoEnvelope(),
        _rng = rng ?? Random.secure();

  final Argon2id _kdf;
  final CryptoEnvelope _envelope;
  final Random _rng;

  static Argon2id _defaultKdf() => Argon2id(
        memory: 65536, // 64 MiB (in KiB per cryptography package)
        parallelism: 1,
        iterations: 3,
        hashLength: 32,
      );

  /// Generates an 8-character Crockford code formatted "XXXX-XXXX".
  String generateCode() {
    final bytes = Uint8List.fromList(
      List<int>.generate(5, (_) => _rng.nextInt(256)),
    );
    final raw = CrockfordBase32.encode(bytes); // 8 chars
    return '${raw.substring(0, 4)}-${raw.substring(4, 8)}';
  }

  /// BLAKE2b(normalised(code)). The normaliser strips dashes/whitespace
  /// and uppercases — so the hash matches whether the user typed
  /// "MK29-HFX4", "mk29hfx4", or "MK29 HFX4".
  ///
  /// Named with a trailing underscore to avoid clashing with Object.hashCode.
  Future<Uint8List> hashCode_(String code) async {
    final normalised = _normalise(code);
    // Must match blake2b(..., undefined, 64) in claim_invite Edge Function.
    final hasher = Blake2b(hashLengthInBytes: 64);
    final hash = await hasher.hash(utf8.encode(normalised));
    return Uint8List.fromList(hash.bytes);
  }

  /// Wraps [familyKey] under a key derived from [code] + a fresh 16-byte salt.
  /// AAD = familyId so a wrapped blob cannot be replayed across families.
  Future<WrappedFamilyKey> wrapFamilyKey({
    required String code,
    required Uint8List familyKey,
    required String familyId,
  }) async {
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => _rng.nextInt(256)),
    );
    final kdfKey = await _deriveKey(code: code, salt: salt);
    final wrapped = await _envelope.seal(
      familyKey,
      kdfKey,
      utf8.encode(familyId),
    );
    return WrappedFamilyKey(salt: salt, wrappedKeyEnvelope: wrapped);
  }

  /// Reverses [wrapFamilyKey]. Throws SecretBoxAuthenticationError on bad code,
  /// bad salt, modified envelope, or mismatched familyId.
  Future<Uint8List> unwrapFamilyKey({
    required String code,
    required Uint8List salt,
    required Uint8List wrappedKeyEnvelope,
    required String familyId,
  }) async {
    final kdfKey = await _deriveKey(code: code, salt: salt);
    return _envelope.open(
      wrappedKeyEnvelope,
      kdfKey,
      utf8.encode(familyId),
    );
  }

  Future<SecretKey> _deriveKey({
    required String code,
    required Uint8List salt,
  }) async {
    final normalised = _normalise(code);
    return _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(normalised)),
      nonce: salt,
    );
  }

  String _normalise(String code) {
    return code.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  }
}
