import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'crypto_envelope.dart';

class PreparedSnapshot {
  const PreparedSnapshot({
    required this.encryptedPayload,
    required this.payloadHash,
    required this.wrappedKey,
    required this.salt,
  });

  final Uint8List encryptedPayload;
  final Uint8List payloadHash;
  final Uint8List wrappedKey;
  final Uint8List salt;
}

class RestoredSnapshot {
  const RestoredSnapshot({required this.familyKey, required this.rows});

  final Uint8List familyKey;
  final List<Map<String, dynamic>> rows;
}

class SnapshotService {
  SnapshotService({Argon2id? kdf, Random? rng})
      : _kdf = kdf ?? _defaultKdf(),
        _payloadEnvelope = CryptoEnvelope(useCompression: true),
        _keyEnvelope = CryptoEnvelope(),
        _rng = rng ?? Random.secure();

  final Argon2id _kdf;
  final CryptoEnvelope _payloadEnvelope;
  final CryptoEnvelope _keyEnvelope;
  final Random _rng;

  static Argon2id _defaultKdf() => Argon2id(
        memory: 65536,
        parallelism: 1,
        iterations: 3,
        hashLength: 32,
      );

  Future<PreparedSnapshot> prepare({
    required String passphrase,
    required Uint8List familyKey,
    required String familyId,
    required int keyVersion,
    required int snapshotVersion,
    required List<Map<String, dynamic>> rows,
  }) async {
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => _rng.nextInt(256)),
    );
    final kdfKey = await _deriveKey(passphrase: passphrase, salt: salt);

    final wrappedKey = await _keyEnvelope.seal(
      familyKey,
      kdfKey,
      utf8.encode('snapshot_key|$familyId|$keyVersion'),
    );

    final payloadJson = utf8.encode(jsonEncode({
      'v': 1,
      'family_id': familyId,
      'key_version': keyVersion,
      'snapshot_version': snapshotVersion,
      'snapshot_at': DateTime.now().toUtc().toIso8601String(),
      'rows': rows,
    }));
    final encryptedPayload = await _payloadEnvelope.seal(
      payloadJson,
      kdfKey,
      utf8.encode('snapshot_payload|$familyId|$snapshotVersion'),
    );

    final hashResult = await Sha256().hash(encryptedPayload);
    final payloadHash = Uint8List.fromList(hashResult.bytes);

    return PreparedSnapshot(
      encryptedPayload: encryptedPayload,
      payloadHash: payloadHash,
      wrappedKey: wrappedKey,
      salt: salt,
    );
  }

  Future<RestoredSnapshot> restore({
    required String passphrase,
    required Uint8List encryptedPayload,
    required Uint8List wrappedKey,
    required Uint8List salt,
    required String familyId,
    required int keyVersion,
    required int snapshotVersion,
  }) async {
    final kdfKey = await _deriveKey(passphrase: passphrase, salt: salt);

    final familyKeyBytes = await _keyEnvelope.open(
      wrappedKey,
      kdfKey,
      utf8.encode('snapshot_key|$familyId|$keyVersion'),
    );

    final payloadJsonBytes = await _payloadEnvelope.open(
      encryptedPayload,
      kdfKey,
      utf8.encode('snapshot_payload|$familyId|$snapshotVersion'),
    );

    final payload =
        jsonDecode(utf8.decode(payloadJsonBytes)) as Map<String, dynamic>;
    final rows = (payload['rows'] as List).cast<Map<String, dynamic>>();

    return RestoredSnapshot(
      familyKey: familyKeyBytes,
      rows: rows,
    );
  }

  Future<SecretKey> _deriveKey({
    required String passphrase,
    required Uint8List salt,
  }) =>
      _kdf.deriveKey(
        secretKey: SecretKey(utf8.encode(passphrase)),
        nonce: salt,
      );
}
