// test/features/home/home_timeline_test.dart
//
// Widget tests for the Home screen's chronological "Today" activity feed
// and the bottom-nav "Summary" label.
//
// Coverage:
//   1. [HomeTimelineSliver] renders entries in reverse-chronological order.
//   2. Each row's tap navigates to the correct feature route
//      (with the source row id as a `?id=…` query param).
//   3. The bottom nav exposes the new `navTabSummary` label
//      ("Summary" in en, "สรุป" in th).
//
// These tests intentionally do NOT mount the full [HomeScreen]. The screen
// pulls a sqflite-backed BabyRepository through a FutureProvider, and
// `sqflite_common_ffi` dispatches queries to a background isolate whose
// ports do not pump inside `FakeAsync`. Overriding
// [homeTodayTimelineProvider] with a synchronous `AsyncData` lets us assert
// on the timeline list without any DB or async dance — and is faithful to
// what the production widget reads.

import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/providers/unit_preferences_provider.dart';
import 'package:dreambook/core/router/app_router.dart';
import 'package:dreambook/core/services/unit_preferences.dart';
import 'package:dreambook/core/widgets/scaffold_with_nav_bar.dart';
import 'package:dreambook/features/home/data/home_timeline_provider.dart';
import 'package:dreambook/features/home/presentation/home_screen.dart';
import 'package:dreambook/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FixedUnitPreferences extends UnitPreferencesNotifier {
  _FixedUnitPreferences(this._fixed);
  final UnitPreferences _fixed;
  @override
  UnitPreferences build() => _fixed;
}

const _kBabyId = 'baby-1';

const _unitPrefs = UnitPreferences(
  volume: VolumeUnit.oz,
  weight: WeightUnit.lbOz,
  length: LengthUnit.inches,
  temp: TempUnit.fahrenheit,
  timeFormat: TimeFormat.h24,
  weekStart: WeekStart.sunday,
);

DateTime _t(int hour, int minute) =>
    DateTime(2026, 5, 16, hour, minute);

Feed _feed(String id, DateTime when, {FeedType type = FeedType.bottle, double? oz = 4.0}) =>
    Feed(
      id: id,
      babyId: _kBabyId,
      type: type,
      oz: oz,
      startedAt: when,
      createdAt: when,
      updatedAt: when,
    );

PumpSession _pump(String id, DateTime when) => PumpSession(
      id: id,
      babyId: _kBabyId,
      leftOz: 2.0,
      rightOz: 1.0,
      startedAt: when,
      createdAt: when,
      updatedAt: when,
    );

Diaper _diaper(String id, DateTime when) => Diaper(
      id: id,
      babyId: _kBabyId,
      type: DiaperType.pee,
      occurredAt: when,
      createdAt: when,
      updatedAt: when,
    );

class _RouterRecord {
  final List<String> pushedPaths = [];
}

GoRouter _testRouter(_RouterRecord rec) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(
          body: CustomScrollView(
            slivers: [HomeTimelineSliver(babyId: _kBabyId)],
          ),
        ),
      ),
      // Catch-all destination routes used by the timeline.
      GoRoute(
        path: AppRoutes.feedNew,
        builder: (ctx, state) {
          rec.pushedPaths.add(state.uri.toString());
          return const Scaffold(body: Text('feedNew'));
        },
      ),
      GoRoute(
        path: AppRoutes.pumpNew,
        builder: (ctx, state) {
          rec.pushedPaths.add(state.uri.toString());
          return const Scaffold(body: Text('pumpNew'));
        },
      ),
      GoRoute(
        path: AppRoutes.diaperNew,
        builder: (ctx, state) {
          rec.pushedPaths.add(state.uri.toString());
          return const Scaffold(body: Text('diaperNew'));
        },
      ),
      GoRoute(
        path: AppRoutes.sleep,
        builder: (ctx, state) {
          rec.pushedPaths.add(state.uri.toString());
          return const Scaffold(body: Text('sleep'));
        },
      ),
      GoRoute(
        path: AppRoutes.stash,
        builder: (ctx, state) {
          rec.pushedPaths.add(state.uri.toString());
          return const Scaffold(body: Text('stash'));
        },
      ),
    ],
  );
}

Widget _wrapTimeline({
  required List<HomeTimelineEntry> entries,
  required _RouterRecord rec,
}) {
  return ProviderScope(
    overrides: [
      unitPreferencesProvider.overrideWith(() => _FixedUnitPreferences(_unitPrefs)),
      homeTodayTimelineProvider(_kBabyId)
          .overrideWithValue(AsyncValue.data(entries)),
    ],
    child: MaterialApp.router(
      routerConfig: _testRouter(rec),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

void main() {
  group('HomeTimelineSliver', () {
    testWidgets('renders entries in reverse-chronological order', (tester) async {
      // Build out-of-order on purpose so we verify the sort actually happens
      // somewhere between provider data and the rendered ListView.
      final feed = FeedTimelineEntry(_feed('f1', _t(8, 15)));
      final pump = PumpTimelineEntry(_pump('p1', _t(13, 30)));
      final diaper = DiaperTimelineEntry(_diaper('d1', _t(10, 45)));

      final rec = _RouterRecord();
      await tester.pumpWidget(
        _wrapTimeline(entries: [pump, diaper, feed], rec: rec),
      );
      await tester.pump();

      // All three rows must be present.
      expect(find.text('13:30'), findsOneWidget,
          reason: 'pump @ 13:30 must render');
      expect(find.text('10:45'), findsOneWidget,
          reason: 'diaper @ 10:45 must render');
      expect(find.text('08:15'), findsOneWidget,
          reason: 'feed @ 08:15 must render');

      // Order: pump (13:30) before diaper (10:45) before feed (08:15).
      final pumpCenter = tester.getCenter(find.text('13:30')).dy;
      final diaperCenter = tester.getCenter(find.text('10:45')).dy;
      final feedCenter = tester.getCenter(find.text('08:15')).dy;
      expect(pumpCenter, lessThan(diaperCenter),
          reason: 'freshest event must be highest in list');
      expect(diaperCenter, lessThan(feedCenter),
          reason: 'older event must appear lower');
    });

    testWidgets('empty list renders localized empty-state copy', (tester) async {
      final rec = _RouterRecord();
      await tester.pumpWidget(_wrapTimeline(entries: const [], rec: rec));
      await tester.pump();

      expect(
        find.textContaining('No activity yet today'),
        findsOneWidget,
        reason: 'empty state must surface homeTimelineEmpty',
      );
    });

    testWidgets('tap on feed row pushes /feed/new?id=…', (tester) async {
      final rec = _RouterRecord();
      final feed = FeedTimelineEntry(_feed('feed-abc', _t(9, 0)));
      await tester.pumpWidget(_wrapTimeline(entries: [feed], rec: rec));
      await tester.pump();

      await tester.tap(find.text('09:00'));
      await tester.pumpAndSettle();

      expect(rec.pushedPaths, isNotEmpty);
      expect(rec.pushedPaths.first, '${AppRoutes.feedNew}?id=feed-abc');
    });

    testWidgets('tap on pump row pushes /pump/new?id=…', (tester) async {
      final rec = _RouterRecord();
      final pump = PumpTimelineEntry(_pump('pump-xyz', _t(11, 0)));
      await tester.pumpWidget(_wrapTimeline(entries: [pump], rec: rec));
      await tester.pump();

      await tester.tap(find.text('11:00'));
      await tester.pumpAndSettle();

      expect(rec.pushedPaths.first, '${AppRoutes.pumpNew}?id=pump-xyz');
    });

    testWidgets('tap on diaper row pushes /diaper/new?id=…', (tester) async {
      final rec = _RouterRecord();
      final diaper = DiaperTimelineEntry(_diaper('dia-zzz', _t(7, 5)));
      await tester.pumpWidget(_wrapTimeline(entries: [diaper], rec: rec));
      await tester.pump();

      await tester.tap(find.text('07:05'));
      await tester.pumpAndSettle();

      expect(rec.pushedPaths.first, '${AppRoutes.diaperNew}?id=dia-zzz');
    });
  });

  group('Bottom nav', () {
    GoRouter navRouter() => GoRouter(
          initialLocation: '/',
          routes: [
            ShellRoute(
              builder: (_, __, child) => ScaffoldWithNavBar(child: child),
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, __) => const SizedBox.shrink(),
                ),
                GoRoute(
                  path: '/summary',
                  builder: (_, __) => const SizedBox.shrink(),
                ),
                GoRoute(
                  path: '/stash',
                  builder: (_, __) => const SizedBox.shrink(),
                ),
                GoRoute(
                  path: '/settings',
                  builder: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
          ],
        );

    testWidgets('renders "Summary" label (en)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: navRouter(),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('th')],
            locale: const Locale('en'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Summary'), findsOneWidget);
      // The "Today" label must NOT appear in the bottom nav (it was the
      // old, confusing name for what is actually a daily summary).
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Today'),
        ),
        findsNothing,
      );
    });

    testWidgets('renders "สรุป" label (th)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: navRouter(),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('th')],
            locale: const Locale('th'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('สรุป'), findsOneWidget);
      // "วันนี้" was the old TH label for the Summary tab. It must NOT
      // appear in the bottom nav anymore (it still legitimately appears in
      // other parts of the app — date headers — so we scope to NavigationBar).
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('วันนี้'),
        ),
        findsNothing,
      );
    });
  });
}
