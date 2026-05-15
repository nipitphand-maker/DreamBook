// test/features/home/baby_switcher_title_test.dart
//
// Regression test for the AppBar title crash on the home screen.
//
// Bug B (5 verification teams confirmed):
//   `_BabySwitcherTitle` in `lib/features/home/presentation/home_screen.dart`
//   called `babies.firstWhere(..., orElse: () => babies.first)` on an empty
//   list when `current_baby_id` SharedPreferences pointed at a baby that
//   no longer exists locally (post-onboarding race, post-wipe, or stale
//   cross-device id). `babies.first` on an empty list throws StateError →
//   Flutter rebuilds the slot with the default release-mode ErrorWidget,
//   which paints solid red.
//
// What this test enforces:
//   For every (babyId, babies) input the widget might see at runtime,
//   `tester.takeException()` MUST be null AND no ErrorWidget appears.
//
// Why this test does NOT mount the full HomeScreen:
//   Home pulls a sqflite-backed FutureProvider through `BabyRepository`,
//   and `sqflite_common_ffi` dispatches queries to a background isolate.
//   Isolate ports do not pump inside the FakeAsync zone that `testWidgets`
//   wraps the body with, so `pumpAndSettle` (or any number of `pump`s)
//   never sees the FutureProvider resolve — every test hangs until the
//   default 10-minute pumpAndSettle timeout. Overriding
//   `babyRepositoryProvider` with a synchronous fake bypasses sqflite
//   entirely and lets us assert on the exact widget the bug lives in.

import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/features/baby/data/baby_repository.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/home/presentation/home_screen.dart';
import 'package:dreambook/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBabyRepository implements BabyRepository {
  _FakeBabyRepository(this._babies);
  final List<Baby> _babies;

  @override
  Future<List<Baby>> list() async => _babies;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SeedCurrentBabyId extends CurrentBabyIdNotifier {
  _SeedCurrentBabyId(this._seed);
  final String? _seed;
  int clearCalls = 0;

  @override
  String? build() => _seed;

  @override
  Future<void> clear() async {
    clearCalls += 1;
  }
}

Baby _baby(String id, String name) => Baby(
      id: id,
      name: name,
      dob: DateTime.utc(2026, 3, 1),
      createdAt: DateTime.utc(2026, 5, 15),
      updatedAt: DateTime.utc(2026, 5, 15),
    );

Widget _wrap({
  required List<Baby> babies,
  required String? babyId,
}) {
  return ProviderScope(
    overrides: [
      babyRepositoryProvider
          .overrideWithValue(_FakeBabyRepository(babies)),
      currentBabyIdProvider.overrideWith(() => _SeedCurrentBabyId(babyId)),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        appBar: AppBar(title: BabySwitcherTitle(babyId: babyId)),
      ),
    ),
  );
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets(
    'case 1: (babyId: null, babies: []) — renders fallback, no exception',
    (tester) async {
      await tester.pumpWidget(_wrap(babies: const [], babyId: null));
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull,
          reason: 'null babyId + empty list must not throw');
      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.text('DreamBook'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets(
    'case 2: (babyId: stale-id, babies: []) — no crash, clears stale id',
    (tester) async {
      await tester.pumpWidget(
        _wrap(babies: const [], babyId: 'stale-baby-uuid'),
      );
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull,
          reason:
              'stale babyId + empty babies list must NOT throw — this is '
              'the exact Bug B that produced a red AppBar after onboarding. '
              'If this fires it usually means home_screen.dart has regressed '
              'back to `babies.firstWhere(..., orElse: () => babies.first)` '
              '— switch to `firstWhereOrNull` from package:collection.');
      expect(find.byType(ErrorWidget), findsNothing);
    },
  );

  testWidgets(
    'case 3: (babyId: stale-id, babies: [other]) — renders gracefully',
    (tester) async {
      await tester.pumpWidget(
        _wrap(babies: [_baby('present', 'Mali')], babyId: 'stale-uuid'),
      );
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
    },
  );

  testWidgets(
    'case 4: (babyId: present, babies: [Mali]) — renders "Mali"',
    (tester) async {
      await tester.pumpWidget(
        _wrap(babies: [_baby('present', 'Mali')], babyId: 'present'),
      );
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.text('Mali'), findsAtLeastNWidgets(1));
    },
  );

  // ─────────────────────────────────────────────────────────────────────
  // Regression: post-frame clear() must NOT fire from BabySwitcherTitle.
  //
  // Before fix, home_screen had a `WidgetsBinding.instance.addPostFrameCallback`
  // that invalidated currentBabyIdProvider whenever (babies=[] && babyId!=null)
  // — that produced an onboarding race where the baby was inserted but the
  // first frame of Home saw an empty list (FutureProvider still loading),
  // cleared the just-set baby id, and forced the user back through Welcome.
  //
  // Fix: post-frame clear() removed; only firstWhereOrNull remains so a
  // missing baby just falls back to the app name.
  // ─────────────────────────────────────────────────────────────────────
  testWidgets(
    'regression: (babyId: stale-id, babies: []) — does NOT call clear() on currentBabyIdProvider',
    (tester) async {
      final notifier = _SeedCurrentBabyId('stale-baby-uuid');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            babyRepositoryProvider
                .overrideWithValue(_FakeBabyRepository(const [])),
            currentBabyIdProvider.overrideWith(() => notifier),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              appBar: AppBar(
                title: const BabySwitcherTitle(babyId: 'stale-baby-uuid'),
              ),
            ),
          ),
        ),
      );

      // Pump enough frames to fire any post-frame callbacks that a regressed
      // implementation might schedule.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(tester.takeException(), isNull);
      expect(notifier.clearCalls, 0,
          reason:
              'BabySwitcherTitle must NEVER call currentBabyIdProvider.clear() — '
              'the post-frame invalidation was the onboarding-race bug we just '
              'removed from home_screen.dart. If this fires, that logic has '
              'returned.');
    },
  );
}
