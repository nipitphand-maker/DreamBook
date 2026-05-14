import 'package:dreambook/features/dreambaby_bridge/data/dreambaby_bridge_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DreamBabyBridgeService', () {
    test('provider creates DreamBabyBridgeService', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final service = container.read(dreamBabyBridgeServiceProvider);
      expect(service, isA<DreamBabyBridgeService>());
    });

    test('dreamBabyInstalledProvider is a FutureProvider<bool>', () {
      // Just verify the type — actual URL launch can't be tested without mock channel
      expect(dreamBabyInstalledProvider, isA<FutureProvider<bool>>());
    });
  });
}
