import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/db/migrations/m001_initial.dart';
import 'package:dreambook/core/db/migrations/m002_v2.dart';
import 'package:dreambook/core/db/migrations/m003_v3.dart';
import 'package:dreambook/core/db/migrations/m004_v4.dart';
import 'package:dreambook/core/db/migrations/m005_daily_note.dart';
import 'package:dreambook/core/db/migrations/m006_sync_written_by.dart';
import 'package:dreambook/core/db/migrations/m007_sync_cursors.dart';
import 'package:dreambook/core/db/migrations/migrations.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/features/summary/presentation/daily_summary_screen.dart';
import 'package:dreambook/features/summary/presentation/history_calendar_sheet.dart';
import 'package:dreambook/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Widget _wrap(Widget child, ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
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
  setUpAll(() => sqfliteFfiInit());

  late Database db;
  late ProviderContainer container;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'current_baby_id': 'b1'});
    prefs = await SharedPreferences.getInstance();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 7,
        onCreate: (d, _) async {
          await Migrations([
            m001Initial,
            m002V2,
            m003V3,
            m004V4,
            m005DailyNote,
            m006SyncWrittenBy,
            m007SyncCursors,
          ]).runAll(d);
        },
      ),
    );
    await db.execute('PRAGMA foreign_keys = ON');
    await db.insert('baby', {
      'id': 'b1',
      'name': 'Mali',
      'dob': '2026-03-01',
      'preferred_unit': 'oz',
      'created_at': '2026-05-13T00:00:00.000Z',
      'updated_at': '2026-05-13T00:00:00.000Z',
      'version': 1,
    });
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((_) async => db),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  testWidgets(
    'HistoryCalendarSheet renders the visible month and emits the picked date',
    (tester) async {
      // Pin the visible month to one with no future-date noise: April 2025.
      final initial = DateTime(2025, 4, 15);
      DateTime? picked;

      await tester.pumpWidget(_wrap(
        Builder(builder: (ctx) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  picked = await showModalBottomSheet<DateTime>(
                    context: ctx,
                    isScrollControlled: true,
                    builder: (_) => HistoryCalendarSheet(
                      babyId: 'b1',
                      initialDate: initial,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2026, 12, 31),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          );
        }),
        container,
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Sheet title + month header are visible.
      expect(find.text('Browse history'), findsOneWidget);
      expect(find.text('April 2025'), findsOneWidget);

      // Tap day 10 — the day-cell uses a key derived from the local date str.
      await tester.tap(find.byKey(const ValueKey('history_cal_day_2025-04-10')));
      await tester.pumpAndSettle();

      expect(picked, isNotNull);
      expect(picked!.year, 2025);
      expect(picked!.month, 4);
      expect(picked!.day, 10);
    },
  );

  // The next two tests mount the real DailySummaryScreen, which fans out to
  // several DB-backed providers (feed/pump/diaper/sleep/stash). sqflite's
  // internal lock-watcher uses a 10s Timer that doesn't tick under
  // flutter_test's FakeAsync, so `pumpAndSettle()` will hang. We use
  // `tester.runAsync` to step out of FakeAsync just long enough for the
  // real queries to complete, then re-pump for the UI to settle.

  Future<void> settleWithDb(WidgetTester tester) async {
    await tester.runAsync(() async {
      // Let the DB-backed Future microtasks drain on the real clock.
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets(
    'DailySummaryScreen exposes a calendar button in the AppBar',
    (tester) async {
      await tester.pumpWidget(_wrap(const DailySummaryScreen(), container));
      await settleWithDb(tester);

      final calButton = find.byKey(const Key('summary_calendar_button'));
      expect(calButton, findsOneWidget);
      expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
    },
  );

  testWidgets(
    'tapping the calendar icon opens the HistoryCalendarSheet',
    (tester) async {
      await tester.pumpWidget(_wrap(const DailySummaryScreen(), container));
      await settleWithDb(tester);

      await tester.tap(find.byKey(const Key('summary_calendar_button')));
      await settleWithDb(tester);
      // One more frame for the bottom-sheet animation.
      await tester.pump(const Duration(milliseconds: 300));

      // Sheet title appears.
      expect(find.text('Browse history'), findsOneWidget);
      // And so does the month-navigation header.
      expect(find.byKey(const Key('history_cal_prev_month')), findsOneWidget);
      expect(find.byKey(const Key('history_cal_next_month')), findsOneWidget);
    },
  );

  testWidgets(
    'tapping a past day in the sheet pops it and advances the Summary date',
    (tester) async {
      final today = DateTime.now();
      final yesterday = DateTime(today.year, today.month, today.day)
          .subtract(const Duration(days: 1));
      String two(int n) => n.toString().padLeft(2, '0');
      final ydKey =
          'history_cal_day_${yesterday.year}-${two(yesterday.month)}-${two(yesterday.day)}';

      await tester.pumpWidget(_wrap(const DailySummaryScreen(), container));
      await settleWithDb(tester);

      await tester.tap(find.byKey(const Key('summary_calendar_button')));
      await settleWithDb(tester);
      await tester.pump(const Duration(milliseconds: 300));

      // Tap yesterday in the calendar grid.
      expect(find.byKey(ValueKey(ydKey)), findsOneWidget);
      await tester.tap(find.byKey(ValueKey(ydKey)));
      await settleWithDb(tester);
      // Drain the bottom-sheet exit animation.
      await tester.pump(const Duration(milliseconds: 400));
      // After the date change DailySummaryScreen swaps to
      // dailySummaryForDateProvider — drain those DB calls so no Timer
      // lives past tearDown.
      await settleWithDb(tester);
      await settleWithDb(tester);

      // Sheet has been dismissed.
      expect(find.text('Browse history'), findsNothing);
      // And the AppBar no longer shows "Today" — the date stepped back.
      expect(find.text('Today'), findsNothing);
    },
  );
}
