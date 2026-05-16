import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

// Crockford Base32 — omits I, L, O, U (visual confusion with 1, 1, 0, V)
const _kAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const _kCodeLen = 20; // 20 chars = ~100 bits of entropy

/// Generates and validates 20-character Crockford base32 recovery codes.
/// Displayed as XXXX-XXXX-XXXX-XXXX-XXXX (dashes are cosmetic only).
/// Passed to [RecoveryService] and [SnapshotService] as the passphrase string.
class RecoveryCodeService {
  String generateCode() {
    final rng = Random.secure();
    return String.fromCharCodes(
      List.generate(_kCodeLen, (_) => _kAlphabet.codeUnitAt(rng.nextInt(32))),
    );
  }

  /// Formats a raw 20-char code as `XXXX-XXXX-XXXX-XXXX-XXXX`.
  String formatCode(String raw) {
    final n = normalizeCode(raw);
    final buf = StringBuffer();
    for (var i = 0; i < n.length; i++) {
      if (i > 0 && i % 4 == 0) buf.write('-');
      buf.write(n[i]);
    }
    return buf.toString();
  }

  /// Strips dashes/spaces, uppercases. Use as the canonical form.
  String normalizeCode(String code) =>
      code.replaceAll(RegExp(r'[-\s]'), '').toUpperCase();

  bool validateCode(String code) {
    final n = normalizeCode(code);
    if (n.length != _kCodeLen) return false;
    return n.split('').every(_kAlphabet.contains);
  }

  Future<Uint8List> lookupHash(String code) async {
    final hasher = Blake2b(hashLengthInBytes: 64);
    final hash = await hasher.hash(utf8.encode(normalizeCode(code)));
    return Uint8List.fromList(hash.bytes);
  }
}
