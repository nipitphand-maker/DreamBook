import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/features/pump/presentation/pump_session_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dreambook/l10n/generated/app_localizations.dart';

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
  });
}
