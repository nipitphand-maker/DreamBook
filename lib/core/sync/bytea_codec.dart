// lib/core/sync/bytea_codec.dart
import 'dart:convert';
import 'dart:typed_data';

/// Decodes a Postgres `bytea` column value as it arrives from PostgREST
/// via supabase_flutter. The value can arrive as:
///   * `Uint8List` (rare — direct ByteArray pathway)
///   * `List<int>` (when the row goes through JSON array decoding)
///   * a `String` starting with `\x` (Postgres hex output form; either case)
///   * a plain base64 `String` (PostgREST default since supabase_flutter 2.x)
///
/// Throws [ArgumentError] for any other type — the throw includes the
/// runtimeType so a future encoding format breaks tests loudly rather
/// than silently corrupting ciphertext.
///
/// Kept as a top-level public function (not private, not a method) so the
/// migration linter can `grep`-anchor every call site.
Uint8List decodeBytea(dynamic v) {
  if (v is Uint8List) return v;
  if (v is List) return Uint8List.fromList(v.cast<int>());
  if (v is String) {
    if (v.startsWith(r'\x')) {
      final hex = v.substring(2);
      if (hex.length.isOdd) {
        throw FormatException(
          'bytea: hex literal has odd length (${hex.length}) — refusing to silently truncate', v);
      }
      return Uint8List.fromList(List.generate(
        hex.length ~/ 2,
        (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
      ));
    }
    try {
      return base64Decode(v);
    } on FormatException catch (e) {
      throw ArgumentError(
        'bytea: String is neither hex (\\x...) nor valid base64: ${e.message}');
    }
  }
  throw ArgumentError('bytea: unexpected ${v.runtimeType}');
}
