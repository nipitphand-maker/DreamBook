import 'dart:typed_data';

import 'package:dreambook/core/crypto/family_key_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_fakes/in_memory_secure_storage.dart';

void main() {
  late InMemorySecureStorage storage;
  late FamilyKeyService service;

  setUp(() {
    storage = InMemorySecureStorage();
    service = FamilyKeyService.forTest(storage);
  });

  group('FamilyKeyService', () {
    test('generate() creates and persists a 32-byte key', () async {
      final key = await service.generate(familyId: 'fam-1', keyVersion: 1);
      expect(key.length, 32);
      final stored = await service.read(familyId: 'fam-1');
      expect(stored, isNotNull);
      expect(stored!.bytes, key);
      expect(stored.keyVersion, 1);
    });

    test('read() returns null when no key stored', () async {
      final r = await service.read(familyId: 'never-stored');
      expect(r, isNull);
    });

    test('rotate() replaces key + bumps version', () async {
      final v1 = await service.generate(familyId: 'fam-1', keyVersion: 1);
      final v2 = await service.rotate(familyId: 'fam-1');
      expect(v2.bytes.length, 32);
      expect(v2.keyVersion, 2);
      expect(v2.bytes, isNot(equals(v1)));
      final back = await service.read(familyId: 'fam-1');
      expect(back!.keyVersion, 2);
    });

    test('clear() wipes the entry', () async {
      await service.generate(familyId: 'fam-1', keyVersion: 1);
      await service.clear(familyId: 'fam-1');
      expect(await service.read(familyId: 'fam-1'), isNull);
    });

    test('install() persists externally-derived 32-byte key', () async {
      final bytes = Uint8List.fromList(List<int>.generate(32, (i) => 0x10 + i));
      await service.install(familyId: 'fam-X', bytes: bytes, keyVersion: 7);
      final back = await service.read(familyId: 'fam-X');
      expect(back!.bytes, bytes);
      expect(back.keyVersion, 7);
    });

    test('install() rejects non-32-byte payload', () async {
      expect(
        () => service.install(
          familyId: 'fam-X',
          bytes: Uint8List(16),
          keyVersion: 1,
        ),
        throwsArgumentError,
      );
    });
  });
}
