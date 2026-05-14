import 'dart:typed_data';

/// Crockford base32 codec.
///
/// Alphabet: 0-9 A-Z minus I, L, O, U (32 chars).
/// Decode collapses common typos: i/I/l/L → 1, o/O → 0, lowercase → uppercase.
/// U/u always reject — they are explicitly excluded from the alphabet.
class CrockfordBase32 {
  CrockfordBase32._();

  static const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// Encodes bytes to a string. Output length = ceil(bytes.length * 8 / 5).
  static String encode(List<int> bytes) {
    if (bytes.isEmpty) return '';
    final out = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final b in bytes) {
      buffer = (buffer << 8) | (b & 0xFF);
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        out.write(_alphabet[(buffer >> bits) & 0x1F]);
      }
    }
    if (bits > 0) {
      out.write(_alphabet[(buffer << (5 - bits)) & 0x1F]);
    }
    return out.toString();
  }

  /// Decodes a Crockford-encoded string. Applies collapse rules:
  /// lowercase → uppercase, I/L → 1, O → 0. U/u throw FormatException.
  static Uint8List decode(String input) {
    if (input.isEmpty) return Uint8List(0);
    var buffer = 0;
    var bits = 0;
    final out = <int>[];
    for (final raw in input.split('')) {
      var c = raw.toUpperCase();
      if (c == '-' || c == ' ') continue; // group separators allowed
      if (c == 'I' || c == 'L') c = '1';
      if (c == 'O') c = '0';
      if (c == 'U') {
        throw const FormatException('Crockford alphabet excludes U');
      }
      final value = _alphabet.indexOf(c);
      if (value < 0) {
        throw FormatException('Not a Crockford base32 character: $raw');
      }
      buffer = (buffer << 5) | value;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xFF);
      }
    }
    return Uint8List.fromList(out);
  }
}
