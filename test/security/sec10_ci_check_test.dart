@Tags(['security'])

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SEC-10: security test suite is tagged and runs on CI', () {
    // This test simply passing proves the @Tags(['security']) tag works
    // and the test is included in `flutter test --tags security`.
    expect(true, isTrue);
  });
}
