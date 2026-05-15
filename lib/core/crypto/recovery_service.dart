import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'crypto_envelope.dart';

/// Output of [RecoveryService.wrapFamilyKey].
class WrappedRecoveryKey {
  const WrappedRecoveryKey({required this.salt, required this.wrappedKey});

  final Uint8List salt;
  final Uint8List wrappedKey;
}

/// BIP-39 recovery: wraps/unwraps K_family under a key derived from the
/// user's mnemonic phrase via Argon2id.
///
/// Per spec §5.3:
/// - KDF = Argon2id m=64 MiB, t=3, p=1, len=32
/// - Wrap = AES-GCM(K_kdf, K_family, aad="$familyId|$keyVersion")
/// - A fresh 16-byte salt is generated per wrap, so two wraps of the same
///   phrase produce different ciphertext (semantic security).
class RecoveryService {
  RecoveryService({
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
        memory: 65536, // 64 MiB (value is in KiB per cryptography package)
        parallelism: 1,
        iterations: 3,
        hashLength: 32,
      );

  Future<WrappedRecoveryKey> wrapFamilyKey({
    required String normalizedPhrase,
    required Uint8List familyKey,
    required String familyId,
    required int keyVersion,
  }) async {
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => _rng.nextInt(256)),
    );
    final kdfKey = await _deriveKey(phrase: normalizedPhrase, salt: salt);
    final sealed = await _envelope.seal(
      familyKey,
      kdfKey,
      utf8.encode('$familyId|$keyVersion'),
    );
    return WrappedRecoveryKey(wrappedKey: sealed, salt: salt);
  }

  Future<Uint8List> unwrapFamilyKey({
    required String normalizedPhrase,
    required Uint8List wrappedKey,
    required Uint8List salt,
    required String familyId,
    required int keyVersion,
  }) async {
    final kdfKey = await _deriveKey(phrase: normalizedPhrase, salt: salt);
    return _envelope.open(
      wrappedKey,
      kdfKey,
      utf8.encode('$familyId|$keyVersion'),
    );
  }

  Future<SecretKey> _deriveKey({
    required String phrase,
    required Uint8List salt,
  }) async {
    return _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(phrase)),
      nonce: salt,
    );
  }
}
