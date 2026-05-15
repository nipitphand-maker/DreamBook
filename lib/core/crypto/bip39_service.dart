import 'dart:convert';
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:cryptography/cryptography.dart';

class Bip39Service {
  String generatePhrase() => bip39.generateMnemonic();

  bool validatePhrase(String phrase) =>
      bip39.validateMnemonic(normalizePhrase(phrase));

  String normalizePhrase(String phrase) =>
      phrase.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  List<String> toWords(String phrase) => normalizePhrase(phrase).split(' ');

  Future<Uint8List> lookupHash(String phrase) async {
    final hasher = Blake2b(hashLengthInBytes: 64);
    final hash = await hasher.hash(utf8.encode(normalizePhrase(phrase)));
    return Uint8List.fromList(hash.bytes);
  }
}
