// test/features/onboarding/welcome_recovery_ux_test.dart
//
// Recovery-UX 2026-05-16 regression guard.
//
// User research showed parents do not understand 12-word BIP39 seed phrases —
// Cloud Backup (server-stored, passphrase-wrapped) is the only realistic
// recovery story for the 0–24 mo audience. We therefore:
//
//   1. REMOVED the "Restore from recovery phrase" entry from the Welcome
//      screen — BIP39 must NOT be surfaced during onboarding.
//   2. KEPT the "Restore from cloud backup" entry as the primary recovery
//      path for returning users.
//
// This test pins both invariants so future contributors don't accidentally
// re-add the seed-phrase link to onboarding.

import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/features/onboarding/presentation/welcome_screen.dart';
import 'package:dreambook/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child, SharedPreferences prefs) {
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

void main() {
  group('WelcomeScreen recovery UX', () {
    testWidgets(
      'does NOT surface BIP39 recovery-phrase restore link',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        await tester.pumpWidget(_wrap(const WelcomeScreen(), prefs));
        await tester.pump();

        // The English string "Restore from recovery phrase" used to live
        // on this screen via `welcomeRestoreCta` — it MUST no longer be
        // rendered. Even partial substring matches would be a regression.
        expect(find.textContaining('recovery phrase'), findsNothing,
            reason:
                'BIP39 recovery-phrase entry must be removed from the '
                'Welcome screen — it now lives in Settings → Advanced.');
        expect(find.textContaining('Recovery phrase'), findsNothing,
            reason: 'Capitalised variant must also be absent.');
      },
    );

    testWidgets(
      'still offers Cloud Backup restore as the primary recovery path',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        await tester.pumpWidget(_wrap(const WelcomeScreen(), prefs));
        await tester.pump();

        // Cloud Backup restore stays on the welcome screen — it's the
        // default recovery path for new users on a new phone.
        expect(find.textContaining('cloud backup'), findsOneWidget,
            reason:
                'Welcome screen must keep the cloud-backup restore entry '
                'as the default recovery option for parents.');
      },
    );
  });
}
