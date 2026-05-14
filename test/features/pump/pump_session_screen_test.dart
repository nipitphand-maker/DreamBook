import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/features/pump/presentation/pump_session_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dreambook/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Bottle splitting logic (mirrors _computeBottles in pump_session_screen.dart)
// ---------------------------------------------------------------------------

List<double> computeBottles(double totalOz, double portionOz) {
  if (totalOz <= 0 || portionOz <= 0) return [];
  final result = <double>[];
  double remaining = totalOz;
  while (remaining > 0.01) {
    final portion = remaining >= portionOz
        ? portionOz
        : double.parse(remaining.toStringAsFixed(1));
    result.add(portion);
    remaining -= portion;
  }
  return result;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrapScreen(Widget child, SharedPreferences prefs) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PumpSessionScreen', () {
    // Test 1: Widget smoke test — renders Start button, no crash
    testWidgets('renders Start button when no timer has been started',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(_wrapScreen(const PumpSessionScreen(), prefs));
      await tester.pump();

      // Start button should be visible (timer not yet started)
      expect(find.text('Start'), findsOneWidget);
      // No Stop or Save in initial state
      expect(find.text('Stop'), findsNothing);
      expect(find.text('Save'), findsNothing);
    });

    // Test 2: Unit timer-persistence test
    // When SharedPreferences already has pump.timerStartedAt set to 10 minutes
    // ago, the screen should recover and show elapsed > 0 (not stuck at 0:00).
    testWidgets('recovers in-progress timer from SharedPreferences',
        (tester) async {
      final tenMinutesAgo =
          DateTime.now().subtract(const Duration(minutes: 10));

      SharedPreferences.setMockInitialValues({
        'pump.timerStartedAt': tenMinutesAgo.toIso8601String(),
        'pump.timerPausedDurSec': 0,
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(_wrapScreen(const PumpSessionScreen(), prefs));
      // Allow initState to complete and the first frame to render
      await tester.pump();

      // The timer should have been recovered: Stop | Pause buttons visible
      // (because _timerRunning = true after recovery)
      expect(find.text('Stop'), findsOneWidget);
      expect(find.text('Pause'), findsOneWidget);

      // Elapsed display should not show 0:00 — it should show ~10 minutes
      // We check the timer text is NOT the zero state (00:00)
      expect(find.text('00:00'), findsNothing);
    });

    // Test 3: Unit test — computeBottles splitting logic
    test('computeBottles splits total oz into correct portions', () {
      expect(computeBottles(10.0, 4.0), [4.0, 4.0, 2.0]);
      expect(computeBottles(8.0, 4.0), [4.0, 4.0]);
      expect(computeBottles(0.0, 4.0), <double>[]);
      expect(computeBottles(3.5, 4.0), [3.5]);
    });

    // Test 4: Widget test — bottle chips appear when saveToStash=true and oz > 0
    testWidgets('bottle chips appear when saveToStash=true and oz > 0',
        (tester) async {
      SharedPreferences.setMockInitialValues({'pump.saveToStash': true});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(_wrapScreen(const PumpSessionScreen(), prefs));
      await tester.pump();

      // Tap the Left oz + button a few times to set left oz > 0
      // The + button for Left oz is the first IconButton.filled with add icon
      final addButtons = find.byIcon(Icons.add);
      // There are two stepper add buttons (Left + Right), tap the first (Left)
      await tester.tap(addButtons.first);
      await tester.pump();
      await tester.tap(addButtons.first);
      await tester.pump();
      await tester.tap(addButtons.first);
      await tester.pump();

      // After 3 taps × 0.5 oz = 1.5 oz total — saveToStash is true → chips shown
      expect(find.byType(InputChip), findsAtLeastNWidgets(1));
    });
  });
}
