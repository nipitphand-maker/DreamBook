import 'package:flutter_test/flutter_test.dart';

// Unit tests for the pump chip label logic that mirrors _LastPumpChip._label
// in lib/features/home/presentation/home_screen.dart.
//
// These are pure Dart tests — no widget setup or DB required.

String pumpLabel(DateTime startedAt, double leftOz, double rightOz) {
  final diff = DateTime.now().difference(startedAt);
  final timeStr =
      diff.inMinutes < 60 ? '${diff.inMinutes}m ago' : '${diff.inHours}h ago';
  final total = leftOz + rightOz;
  final ozStr = total > 0 ? ' · ${total.toStringAsFixed(1)} oz' : '';
  return 'Pump · $timeStr$ozStr';
}

void main() {
  group('pump chip label', () {
    test('shows minutes when < 1h', () {
      final label = pumpLabel(
          DateTime.now().subtract(const Duration(minutes: 30)), 3.0, 2.0);
      expect(label, contains('30m ago'));
      expect(label, contains('5.0 oz'));
    });

    test('shows hours when >= 1h', () {
      final label = pumpLabel(
          DateTime.now().subtract(const Duration(hours: 2)), 0, 0);
      expect(label, contains('2h ago'));
      expect(label, isNot(contains('oz')));
    });
  });
}
