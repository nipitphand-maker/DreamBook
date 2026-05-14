import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// AES-GCM-256 envelope: `nonce(12) || ciphertext(N) || mac(16)`.
///
/// Per spec §3.1 and §5.1, the AAD must be the canonical row identity
/// `"${table}|${record_id}|${version}|${family_id}|${key_version}"` so a
/// tampered metadata field invalidates the MAC and the row is rejected.
class CryptoEnvelope {
  CryptoEnvelope({AesGcm? algorithm})
      : _aes = algorithm ?? AesGcm.with256bits();

  final AesGcm _aes;

  /// Seals [plaintext] under [key] with [aad]. Returns the envelope bytes.
  Future<Uint8List> seal(
    List<int> plaintext,
    SecretKey key,
    List<int> aad,
  ) async {
    final box = await _aes.encrypt(
      plaintext,
      secretKey: key,
      aad: aad,
    );
    final out = Uint8List(box.nonce.length + box.cipherText.length + box.mac.bytes.length);
    out.setRange(0, box.nonce.length, box.nonce);
    out.setRange(box.nonce.length, box.nonce.length + box.cipherText.length, box.cipherText);
    out.setRange(box.nonce.length + box.cipherText.length, out.length, box.mac.bytes);
    return out;
  }

  /// Opens [envelope] under [key] with [aad]. Returns plaintext or throws
  /// [SecretBoxAuthenticationError] on any mismatch (wrong key, tampered AAD,
  /// modified ciphertext, modified MAC).
  Future<Uint8List> open(
    Uint8List envelope,
    SecretKey key,
    List<int> aad,
  ) async {
    const nonceLen = 12;
    const macLen = 16;
    if (envelope.length < nonceLen + macLen) {
      throw const FormatException('Envelope too short');
    }
    final nonce = envelope.sublist(0, nonceLen);
    final ct = envelope.sublist(nonceLen, envelope.length - macLen);
    final mac = envelope.sublist(envelope.length - macLen);
    final box = SecretBox(ct, nonce: nonce, mac: Mac(mac));
    final pt = await _aes.decrypt(box, secretKey: key, aad: aad);
    return Uint8List.fromList(pt);
  }
}
