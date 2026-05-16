import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/features/diaper/data/diaper_stock_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
  });

  tearDown(() => container.dispose());

  group('DiaperStock', () {
    test('fraction is 0 when initial is 0 (defensive)', () {
      expect(const DiaperStock(initial: 0, current: 0).fraction, 0.0);
    });

    test('fraction is 0.5 when current=50, initial=100', () {
      expect(const DiaperStock(initial: 100, current: 50).fraction, 0.5);
    });

    test('isCritical true when current=0', () {
      expect(const DiaperStock(initial: 80, current: 0).isCritical, isTrue);
    });

    test('isCritical true when fraction=0.10 (exactly 10%)', () {
      expect(const DiaperStock(initial: 100, current: 10).isCritical, isTrue);
    });

    test('isCritical true when fraction=0.05', () {
      expect(const DiaperStock(initial: 100, current: 5).isCritical, isTrue);
    });

    test('isCritical false when fraction=0.11', () {
      expect(const DiaperStock(initial: 100, current: 11).isCritical, isFalse);
    });

    test('isWarning true when fraction=0.20 (between 10 and 25)', () {
      expect(const DiaperStock(initial: 100, current: 20).isWarning, isTrue);
    });

    test('isWarning true when fraction=0.25 (exactly 25%)', () {
      expect(const DiaperStock(initial: 100, current: 25).isWarning, isTrue);
    });

    test('isWarning false when fraction=0.10 (critical, not warning)', () {
      expect(const DiaperStock(initial: 100, current: 10).isWarning, isFalse);
    });

    test('isWarning false when fraction=0.26 (above warning threshold)', () {
      expect(const DiaperStock(initial: 100, current: 26).isWarning, isFalse);
    });

    test('shouldAlert equals isCritical OR isWarning', () {
      const critical = DiaperStock(initial: 100, current: 5);
      expect(critical.shouldAlert, critical.isCritical || critical.isWarning);
      expect(critical.shouldAlert, isTrue);

      const warning = DiaperStock(initial: 100, current: 20);
      expect(warning.shouldAlert, warning.isCritical || warning.isWarning);
      expect(warning.shouldAlert, isTrue);

      const safe = DiaperStock(initial: 100, current: 80);
      expect(safe.shouldAlert, safe.isCritical || safe.isWarning);
      expect(safe.shouldAlert, isFalse);
    });

    test('shouldAlert false when fraction > 0.25', () {
      expect(
        const DiaperStock(initial: 100, current: 26).shouldAlert,
        isFalse,
      );
      expect(
        const DiaperStock(initial: 100, current: 50).shouldAlert,
        isFalse,
      );
      expect(
        const DiaperStock(initial: 100, current: 100).shouldAlert,
        isFalse,
      );
    });
  });

  group('DiaperStockService', () {
    test('restock sets both initial and current to packSize', () async {
      await DiaperStockService.restock(prefs, 'b1', 80);
      container.invalidate(diaperStockProvider('b1'));
      final stock = container.read(diaperStockProvider('b1'));
      expect(stock?.initial, 80);
      expect(stock?.current, 80);
    });

    test('decrement after restock(80) — current becomes 79, initial stays 80',
        () async {
      await DiaperStockService.restock(prefs, 'b1', 80);
      await DiaperStockService.decrement(prefs, 'b1');
      container.invalidate(diaperStockProvider('b1'));
      final stock = container.read(diaperStockProvider('b1'));
      expect(stock?.initial, 80);
      expect(stock?.current, 79);
    });

    test('decrement clamps at 0 — decrement when current=0 stays 0', () async {
      await DiaperStockService.restock(prefs, 'b1', 2);
      await DiaperStockService.decrement(prefs, 'b1'); // 1
      await DiaperStockService.decrement(prefs, 'b1'); // 0
      await DiaperStockService.decrement(prefs, 'b1'); // stays 0
      await DiaperStockService.decrement(prefs, 'b1'); // stays 0
      container.invalidate(diaperStockProvider('b1'));
      final stock = container.read(diaperStockProvider('b1'));
      expect(stock?.initial, 2);
      expect(stock?.current, 0);
    });

    test('decrement is a no-op when tracking not enabled', () async {
      // No restock call → no keys set.
      await DiaperStockService.decrement(prefs, 'b1');
      container.invalidate(diaperStockProvider('b1'));
      expect(container.read(diaperStockProvider('b1')), isNull);
      // Confirm raw prefs were not written.
      expect(prefs.getInt('diaper.stock.b1.initial'), isNull);
      expect(prefs.getInt('diaper.stock.b1.current'), isNull);
    });

    test('setCurrent(50) after restock(80) — current = 50', () async {
      await DiaperStockService.restock(prefs, 'b1', 80);
      await DiaperStockService.setCurrent(prefs, 'b1', 50);
      container.invalidate(diaperStockProvider('b1'));
      final stock = container.read(diaperStockProvider('b1'));
      expect(stock?.initial, 80);
      expect(stock?.current, 50);
    });

    test('setCurrent clamps to initial: setCurrent(100) when initial=80 → 80',
        () async {
      await DiaperStockService.restock(prefs, 'b1', 80);
      await DiaperStockService.setCurrent(prefs, 'b1', 100);
      container.invalidate(diaperStockProvider('b1'));
      final stock = container.read(diaperStockProvider('b1'));
      expect(stock?.initial, 80);
      expect(stock?.current, 80);
    });

    test('setCurrent clamps to 0: setCurrent(-5) → 0', () async {
      await DiaperStockService.restock(prefs, 'b1', 80);
      await DiaperStockService.setCurrent(prefs, 'b1', -5);
      container.invalidate(diaperStockProvider('b1'));
      final stock = container.read(diaperStockProvider('b1'));
      expect(stock?.initial, 80);
      expect(stock?.current, 0);
    });

    test('setCurrent is a no-op when tracking not enabled', () async {
      await DiaperStockService.setCurrent(prefs, 'b1', 50);
      container.invalidate(diaperStockProvider('b1'));
      expect(container.read(diaperStockProvider('b1')), isNull);
      expect(prefs.getInt('diaper.stock.b1.initial'), isNull);
      expect(prefs.getInt('diaper.stock.b1.current'), isNull);
    });

    test('clear removes both keys — provider returns null after', () async {
      await DiaperStockService.restock(prefs, 'b1', 80);
      container.invalidate(diaperStockProvider('b1'));
      expect(container.read(diaperStockProvider('b1')), isNotNull);

      await DiaperStockService.clear(prefs, 'b1');
      container.invalidate(diaperStockProvider('b1'));
      expect(container.read(diaperStockProvider('b1')), isNull);
      expect(prefs.getInt('diaper.stock.b1.initial'), isNull);
      expect(prefs.getInt('diaper.stock.b1.current'), isNull);
    });
  });

  group('diaperStockProvider', () {
    test('returns null when no keys set', () {
      expect(container.read(diaperStockProvider('b1')), isNull);
    });

    test('returns DiaperStock with correct values after restock', () async {
      await DiaperStockService.restock(prefs, 'b1', 80);
      container.invalidate(diaperStockProvider('b1'));
      final stock = container.read(diaperStockProvider('b1'));
      expect(stock, isNotNull);
      expect(stock!.initial, 80);
      expect(stock.current, 80);
      expect(stock.fraction, 1.0);
      expect(stock.isCritical, isFalse);
      expect(stock.isWarning, isFalse);
      expect(stock.shouldAlert, isFalse);
    });

    test('reflects new value after restock + invalidate', () async {
      await DiaperStockService.restock(prefs, 'b1', 80);
      container.invalidate(diaperStockProvider('b1'));
      expect(container.read(diaperStockProvider('b1'))?.current, 80);

      // Restock to a different size — invalidate to pick up the change.
      await DiaperStockService.restock(prefs, 'b1', 40);
      container.invalidate(diaperStockProvider('b1'));
      final stock = container.read(diaperStockProvider('b1'));
      expect(stock?.initial, 40);
      expect(stock?.current, 40);
    });

    test('two babies have independent stocks', () async {
      await DiaperStockService.restock(prefs, 'b1', 80);
      container.invalidate(diaperStockProvider('b1'));
      container.invalidate(diaperStockProvider('b2'));

      final b1 = container.read(diaperStockProvider('b1'));
      final b2 = container.read(diaperStockProvider('b2'));
      expect(b1?.initial, 80);
      expect(b1?.current, 80);
      expect(b2, isNull);

      // Now restock b2 with a different size and decrement it once;
      // b1 should be untouched.
      await DiaperStockService.restock(prefs, 'b2', 30);
      await DiaperStockService.decrement(prefs, 'b2');
      container.invalidate(diaperStockProvider('b1'));
      container.invalidate(diaperStockProvider('b2'));

      final b1After = container.read(diaperStockProvider('b1'));
      final b2After = container.read(diaperStockProvider('b2'));
      expect(b1After?.initial, 80);
      expect(b1After?.current, 80);
      expect(b2After?.initial, 30);
      expect(b2After?.current, 29);
    });
  });
}
