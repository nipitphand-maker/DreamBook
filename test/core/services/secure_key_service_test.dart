import 'package:dreambook/core/services/secure_key_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // In-memory fake for flutter_secure_storage via MethodChannel.
  final fakeStorage = <String, String>{};
  setUp(() {
    fakeStorage.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        switch (call.method) {
          case 'read':
            return fakeStorage[(call.arguments as Map)['key']];
          case 'write':
            final args = call.arguments as Map;
            fakeStorage[args['key']! as String] = args['value']! as String;
            return null;
          case 'delete':
            fakeStorage.remove((call.arguments as Map)['key']);
            return null;
          case 'deleteAll':
            fakeStorage.clear();
            return null;
        }
        return null;
      },
    );
  });

  test('getOrCreateDbKey returns same key on subsequent calls', () async {
    final a = await SecureKeyService.getOrCreateDbKey();
    final b = await SecureKeyService.getOrCreateDbKey();
    expect(a, b);
    expect(a.length, greaterThanOrEqualTo(32));
  });

  test('keys are url-safe base64', () async {
    final k = await SecureKeyService.getOrCreateDbKey();
    expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(k), isTrue);
  });
}
