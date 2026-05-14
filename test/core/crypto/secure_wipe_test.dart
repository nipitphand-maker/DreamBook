import 'dart:typed_data';

import 'package:dreambook/core/crypto/secure_wipe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('secureWipe', () {
    test('zeroes all bytes of a Uint8List in place', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      secureWipe(bytes);
      expect(bytes, Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 0]));
    });

    test('is safe on empty Uint8List', () {
      final bytes = Uint8List(0);
      secureWipe(bytes);
      expect(bytes.length, 0);
    });
  });
}
