import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dreambook/core/crypto/crypto_envelope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zstandard/zstandard.dart';

void main() {
  late SecretKey key;

  /// Whether native zstd FFI is available in this test environment.
  /// Flutter unit tests on macOS (no macOS runner) cannot load the
  /// zstandard_macos.framework, so compression silently falls back to v1.
  /// We probe once and skip v2-specific assertions when unavailable.
  bool zstdAvailable = false;

  setUp(() async {
    key = await AesGcm.with256bits().newSecretKey();
    try {
      final probe = await Zstandard().compress(
        Uint8List.fromList([0x41, 0x41, 0x41, 0x41, 0x41]),
        3,
      );
      zstdAvailable = probe != null;
    } catch (_) {
      zstdAvailable = false;
    }
  });

  group('CryptoEnvelope versioned (zstd)', () {
    test('v1 round-trip: seal+open without compression', () async {
      final env = CryptoEnvelope(useCompression: false);
      final plaintext = utf8.encode('hello world from v1');
      final aad = utf8.encode('feed|r1|1|fam|1');
      final ct = await env.seal(plaintext, key, aad);
      expect(ct[0], 0x01); // version byte
      final back = await env.open(ct, key, aad);
      expect(back, plaintext);
    });

    test('v2 round-trip: seal compresses, open decompresses', () async {
      final env = CryptoEnvelope(useCompression: true);
      // Use a large compressible payload to ensure v2 path is taken
      final plaintext = utf8.encode('A' * 1000);
      final aad = utf8.encode('feed|r1|1|fam|1');
      final ct = await env.seal(plaintext, key, aad);

      if (zstdAvailable) {
        // Native zstd available — must produce v2 (compressed) envelope.
        expect(ct[0], 0x02, reason: 'Expected v2 version byte when zstd is available');
      } else {
        // Native zstd not available in this test environment (no macOS runner).
        // Compression silently falls back to v1 — envelope must still be valid.
        expect(ct[0], 0x01, reason: 'Falls back to v1 when zstd FFI unavailable');
      }

      // Either way, round-trip must be correct.
      final back = await env.open(ct, key, aad);
      expect(back, plaintext);
    });

    test('v2-reads-v1: CryptoEnvelope(useCompression: true) can open v1 envelope', () async {
      final v1env = CryptoEnvelope(useCompression: false);
      final v2env = CryptoEnvelope(useCompression: true);
      final plaintext = utf8.encode('cross-version payload');
      final aad = utf8.encode('feed|r2|1|fam|1');
      final v1ct = await v1env.seal(plaintext, key, aad);
      expect(v1ct[0], 0x01);
      final back = await v2env.open(v1ct, key, aad);
      expect(back, plaintext);
    });

    test('AAD tamper fails on v2 envelope', () async {
      final env = CryptoEnvelope(useCompression: true);
      final plaintext = utf8.encode('A' * 500);
      final aad = utf8.encode('feed|r1|1|fam|1');
      final ct = await env.seal(plaintext, key, aad);
      final tamperedAad = utf8.encode('feed|r1|2|fam|1');
      await expectLater(
        () => env.open(ct, key, tamperedAad),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });
}
