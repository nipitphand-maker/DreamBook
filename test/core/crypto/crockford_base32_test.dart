import 'dart:typed_data';

import 'package:dreambook/core/crypto/crockford_base32.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CrockfordBase32', () {
    test('encodes 5-byte input to 8-char string from official alphabet', () {
      final bytes = Uint8List.fromList([0x12, 0x34, 0x56, 0x78, 0x9A]);
      final s = CrockfordBase32.encode(bytes);
      expect(s.length, 8);
      expect(RegExp(r'^[0-9A-HJKMNP-TV-Z]+$').hasMatch(s), isTrue);
    });

    test('round-trip 10k random 5-byte payloads', () {
      for (var i = 0; i < 10000; i++) {
        final bytes = Uint8List.fromList(
          List<int>.generate(5, (_) => (i * 7 + 13) & 0xFF),
        );
        final s = CrockfordBase32.encode(bytes);
        final back = CrockfordBase32.decode(s);
        expect(back, bytes, reason: 'round-trip failed at iteration $i');
      }
    });

    test('decode collapses ambiguous chars (i/I/l/L → 1, o/O → 0)', () {
      // 'IL01' should decode same as '1101' after normalisation.
      final a = CrockfordBase32.decode('1101AAAA');
      final b = CrockfordBase32.decode('iLO1AAAA');
      expect(b, a);
    });

    test('decode rejects U (Crockford excludes it)', () {
      expect(
        () => CrockfordBase32.decode('UUUUUUUU'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
