import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:zstandard/zstandard.dart';

const int _vLegacy = 0x01;
const int _vCompressed = 0x02;

/// Versioned AES-GCM-256 envelope with optional zstd compression.
///
/// ## Format
/// - v1 (legacy, no compression):  `0x01 || nonce(12) || ciphertext(N) || mac(16)`
/// - v2 (zstd compressed):         `0x02 || nonce(12) || compressed_ciphertext(N) || mac(16)`
///
/// The version byte is folded into the AAD (prepended before AES-GCM seal/open),
/// so tampering with the version byte invalidates the MAC.
///
/// Per spec §3.1 and §5.1, the AAD must be the canonical row identity
/// `"${table}|${record_id}|${version}|${family_id}|${key_version}"` so a
/// tampered metadata field invalidates the MAC and the row is rejected.
class CryptoEnvelope {
  CryptoEnvelope({this.useCompression = false, AesGcm? algorithm})
      : _aes = algorithm ?? AesGcm.with256bits();

  /// When true, [seal] will attempt zstd compression before encrypting.
  /// If compression fails or produces output larger than the original,
  /// falls back to v1 (uncompressed) silently.
  final bool useCompression;
  final AesGcm _aes;

  /// Seals [plaintext] under [key] with [aad].
  ///
  /// Returns a versioned envelope: `version(1) || nonce(12) || ciphertext(N) || mac(16)`.
  /// Uses v2 (compressed) when [useCompression] is true and compression wins;
  /// otherwise uses v1 (uncompressed).
  Future<Uint8List> seal(
    List<int> plaintext,
    SecretKey key,
    List<int> aad,
  ) async {
    int version = _vLegacy;
    List<int> payload = plaintext;

    if (useCompression) {
      try {
        final compressed = await Zstandard().compress(
          Uint8List.fromList(plaintext),
          3, // default compression level
        );
        if (compressed != null && compressed.length < plaintext.length) {
          payload = compressed;
          version = _vCompressed;
        }
      } catch (_) {
        // Compression failed — fall back to v1 silently.
      }
    }

    final versionedAad = [version, ...aad];
    final box = await _aes.encrypt(payload, secretKey: key, aad: versionedAad);

    final inner = Uint8List(
      box.nonce.length + box.cipherText.length + box.mac.bytes.length,
    );
    inner.setRange(0, box.nonce.length, box.nonce);
    inner.setRange(
      box.nonce.length,
      box.nonce.length + box.cipherText.length,
      box.cipherText,
    );
    inner.setRange(
      box.nonce.length + box.cipherText.length,
      inner.length,
      box.mac.bytes,
    );

    final out = Uint8List(1 + inner.length);
    out[0] = version;
    out.setRange(1, out.length, inner);
    return out;
  }

  /// Opens a versioned [envelope] under [key] with [aad].
  ///
  /// Sniffs the version byte (v1 or v2) and decrypts accordingly.
  /// For v2 envelopes, decompresses the plaintext after decryption.
  /// Throws [SecretBoxAuthenticationError] on any integrity failure.
  /// Throws [FormatException] on malformed input.
  Future<Uint8List> open(
    Uint8List envelope,
    SecretKey key,
    List<int> aad,
  ) async {
    if (envelope.isEmpty) throw const FormatException('Empty envelope');
    final version = envelope[0];
    if (version != _vLegacy && version != _vCompressed) {
      throw FormatException('Unknown envelope version: $version');
    }

    final inner = envelope.sublist(1);
    const nonceLen = 12;
    const macLen = 16;
    if (inner.length < nonceLen + macLen) {
      throw const FormatException('Envelope too short');
    }
    final nonce = inner.sublist(0, nonceLen);
    final ct = inner.sublist(nonceLen, inner.length - macLen);
    final mac = inner.sublist(inner.length - macLen);
    final box = SecretBox(ct, nonce: nonce, mac: Mac(mac));

    final versionedAad = [version, ...aad];
    final pt = await _aes.decrypt(box, secretKey: key, aad: versionedAad);

    if (version == _vCompressed) {
      final decompressed = await Zstandard().decompress(
        Uint8List.fromList(pt),
      );
      if (decompressed == null) {
        throw const FormatException('Decompression failed');
      }
      return Uint8List.fromList(decompressed);
    }

    return Uint8List.fromList(pt);
  }
}
