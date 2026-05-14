import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dreambook/core/crypto/invite_code_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InviteCodeService service;

  setUp(() {
    service = InviteCodeService();
  });

  group('InviteCodeService', () {
    test('generateCode() returns 8 Crockford chars in XXXX-XXXX form', () async {
      for (var i = 0; i < 100; i++) {
        final code = service.generateCode();
        expect(code.length, 9, reason: '8 chars + 1 dash');
        expect(code[4], '-');
        final stripped = code.replaceAll('-', '');
        expect(stripped.length, 8);
        expect(RegExp(r'^[0-9A-HJKMNP-TV-Z]+$').hasMatch(stripped), isTrue,
            reason: 'code $code must be Crockford-only');
      }
    });

    test('hashCode produces stable BLAKE2b digest', () async {
      final h1 = await service.hashCode_('MK29-HFX4');
      final h2 = await service.hashCode_('MK29-HFX4');
      expect(h1, h2);
      final h3 = await service.hashCode_('MK29-HFX5');
      expect(h1, isNot(equals(h3)));
    });

    test('hashCode normalises lower-case + ambiguous chars before hashing', () async {
      final h1 = await service.hashCode_('MK29-HFX4');
      final h2 = await service.hashCode_('mk29-hfx4');
      final h3 = await service.hashCode_('MK29HFX4');           // no dash
      expect(h1, h2);
      expect(h1, h3);
    });

    test('wrap then unwrap K_family round-trips', () async {
      const code = 'TEST-CODE'; // 8 valid Crockford chars w/ dash
      final familyKey = Uint8List.fromList(
        List<int>.generate(32, (i) => i),
      );
      const familyId = 'fam-abc-123';
      final wrapped = await service.wrapFamilyKey(
        code: code,
        familyKey: familyKey,
        familyId: familyId,
      );
      expect(wrapped.salt.length, 16);
      expect(wrapped.wrappedKeyEnvelope.length, greaterThan(32));
      final back = await service.unwrapFamilyKey(
        code: code,
        salt: wrapped.salt,
        wrappedKeyEnvelope: wrapped.wrappedKeyEnvelope,
        familyId: familyId,
      );
      expect(back, familyKey);
    });

    test('unwrap fails on wrong code', () async {
      final familyKey = Uint8List.fromList(List<int>.generate(32, (i) => i));
      const familyId = 'fam-1';
      final wrapped = await service.wrapFamilyKey(
        code: 'TEST-CODE',
        familyKey: familyKey,
        familyId: familyId,
      );
      await expectLater(
        () => service.unwrapFamilyKey(
          code: 'WRNG-CODE',
          salt: wrapped.salt,
          wrappedKeyEnvelope: wrapped.wrappedKeyEnvelope,
          familyId: familyId,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });
}
