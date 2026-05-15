// test/core/sync/bytea_codec_test.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dreambook/core/sync/bytea_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decodeBytea', () {
    test('Uint8List passthrough preserves identity content', () {
      final input = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      expect(decodeBytea(input), equals(input));
    });

    test('List<int> from JSON array becomes Uint8List', () {
      final input = <int>[1, 2, 3, 250];
      final out = decodeBytea(input);
      expect(out, isA<Uint8List>());
      expect(out, equals(Uint8List.fromList(input)));
    });

    test(r'PostgREST hex string starting with \x decodes', () {
      // \xDEADBEEF -> [0xDE, 0xAD, 0xBE, 0xEF]
      final out = decodeBytea(r'\xDEADBEEF');
      expect(out, equals(Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF])));
    });

    test('plain base64 string decodes', () {
      final bytes = Uint8List.fromList([10, 20, 30, 40, 50]);
      final encoded = base64Encode(bytes);
      expect(decodeBytea(encoded), equals(bytes));
    });

    test('unsupported type throws ArgumentError with runtimeType', () {
      expect(() => decodeBytea(42), throwsA(isA<ArgumentError>()));
    });
  });
}
