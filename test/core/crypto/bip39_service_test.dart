import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dreambook/core/crypto/bip39_service.dart';

void main() {
  late Bip39Service service;
  setUp(() => service = Bip39Service());

  group('generatePhrase', () {
    test('returns 12 space-separated lowercase words', () {
      final phrase = service.generatePhrase();
      final words = phrase.split(' ');
      expect(words.length, 12);
      for (final w in words) {
        expect(w, equals(w.toLowerCase()));
        expect(w.isNotEmpty, isTrue);
      }
    });

    test('two known phrases are not equal', () {
      const p1 = 'abandon ability able about above absent absorb abstract absurd abuse access accident';
      const p2 = 'zoo zone zone zone zone zone zone zone zone zone zone zoom';
      expect(p1, isNot(equals(p2)));
    });
  });

  group('validatePhrase', () {
    test('valid phrase returns true', () {
      final phrase = service.generatePhrase();
      expect(service.validatePhrase(phrase), isTrue);
    });

    test('garbled phrase returns false', () {
      expect(
        service.validatePhrase('abc def ghi jkl mno pqr stu vwx yza bcd efg hij'),
        isFalse,
      );
    });

    test('validates after normalisation (extra spaces, mixed case)', () {
      final phrase = service.generatePhrase();
      final messy = '  ${phrase.toUpperCase().replaceAll(' ', '  ')}  ';
      expect(service.validatePhrase(messy), isTrue);
    });
  });

  group('normalizePhrase', () {
    test('lowercases and collapses spaces', () {
      const input = '  ABANDON  ABILITY  ABLE  ';
      expect(service.normalizePhrase(input), equals('abandon ability able'));
    });
  });

  group('toWords', () {
    test('splits phrase into 12-element list', () {
      final phrase = service.generatePhrase();
      expect(service.toWords(phrase).length, 12);
    });

    test('normalises before splitting', () {
      const messy = '  ABANDON  ABILITY  ABLE  ';
      expect(service.toWords(messy), equals(['abandon', 'ability', 'able']));
    });
  });

  group('lookupHash', () {
    test('returns 64-byte Uint8List', () async {
      final phrase = service.generatePhrase();
      final hash = await service.lookupHash(phrase);
      expect(hash, isA<Uint8List>());
      expect(hash.length, 64);
    });

    test('same normalised phrase produces same hash', () async {
      const phrase = 'abandon ability able about above absent absorb abstract absurd abuse access accident';
      final h1 = await service.lookupHash(phrase);
      final h2 = await service.lookupHash('  ABANDON  ABILITY  ABLE  ABOUT  ABOVE  ABSENT  ABSORB  ABSTRACT  ABSURD  ABUSE  ACCESS  ACCIDENT  ');
      expect(h1, equals(h2));
    });

    test('different phrases produce different hashes', () async {
      const p1 = 'abandon ability able about above absent absorb abstract absurd abuse access accident';
      const p2 = 'zoo zone zone zone zone zone zone zone zone zone zone zoom';
      final h1 = await service.lookupHash(p1);
      final h2 = await service.lookupHash(p2);
      expect(h1, isNot(equals(h2)));
    });
  });
}
