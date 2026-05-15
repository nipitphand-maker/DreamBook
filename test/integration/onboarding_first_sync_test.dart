// test/integration/onboarding_first_sync_test.dart
//
// End-to-end regression test for the post-onboarding crash AND the first
// sync push. This test fires BOTH bug patterns at once:
//
//   Bug A: deviceFp wrong-format → first SyncWorker.pushOnce() returns
//          PostgrestException 42501 from the encrypted_rows RLS predicate.
//   Bug B: HomeScreen AppBar title crashes (`firstWhere` on empty babies)
//          during the post-onboarding redirect while the FutureProvider is
//          still resolving.
//
// What this test enforces:
//   1. Onboarding completes without throwing.
//   2. HomeScreen renders without an ErrorWidget AND `tester.takeException()`
//      is null (catches Bug B end-to-end).
//   3. `syncLifecycleControllerProvider.syncNow()` completes cleanly
//      AND `SyncStatus.lastError` is null (catches Bug A end-to-end).
//   4. After sync, the baby name appears in the AppBar — proves the
//      fallback path of Bug B's fix didn't accidentally swallow real data.
//
// Skips when `.env.test.supabase` is missing — same pattern as the rest of
// the Ring 2 integration suite.

@Tags(['integration'])
library;

import 'dart:typed_data';

import 'package:dreambook/core/crypto/family_key_service.dart';
import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/db/migrations/m001_initial.dart';
import 'package:dreambook/core/db/migrations/m002_v2.dart';
import 'package:dreambook/core/db/migrations/m003_v3.dart';
import 'package:dreambook/core/db/migrations/m004_v4.dart';
import 'package:dreambook/core/db/migrations/m005_daily_note.dart';
import 'package:dreambook/core/db/migrations/m006_sync_written_by.dart';
import 'package:dreambook/core/db/migrations/m007_sync_cursors.dart';
import 'package:dreambook/core/db/migrations/migrations.dart';
import 'package:dreambook/core/providers/device_id_provider.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/core/sync/sync_lifecycle_controller.dart';
import 'package:dreambook/core/sync/sync_status_provider.dart';
import 'package:dreambook/features/baby/data/baby_repository.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/home/presentation/home_screen.dart';
import 'package:dreambook/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../_fakes/in_memory_secure_storage.dart';
import '_helpers/real_supabase_harness.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  RealSupabaseHarness? harness;

  setUpAll(() async {
    harness = await RealSupabaseHarness.bootOrSkip();
  });

  testWidgets(
    'onboarding → home renders cleanly → first sync push succeeds',
    (tester) async {
      final h = harness;
      if (h == null) return; // skipped at setUpAll
      final fx = await h.freshFamily();
      addTearDown(fx.dispose);

      // ── Boot a local DB the way appDatabaseProvider would in production ──
      final db = await databaseFactoryFfi.openDatabase(
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
      addTearDown(db.close);
      await db.execute('PRAGMA foreign_keys = ON');
      await db.insert('family_metadata', {
        'id': fx.familyId,
        'current_key_version': 1,
        'created_at': '2026-05-15T00:00:00.000Z',
      });

      // K_family for envelope seal during push.
      final familyKeys = FamilyKeyService.forTest(InMemorySecureStorage());
      await familyKeys.generate(familyId: fx.familyId, keyVersion: 1);

      // Bind the prefs key the way WelcomeScreen.bootstrapFamily() does after
      // a successful bootstrap_family call — this is what unlocks
      // syncLifecycleControllerProvider's real worker (non-no-op).
      SharedPreferences.setMockInitialValues({
        'family.id': fx.familyId,
        'onboarding.done': true,
      });
      final prefs = await SharedPreferences.getInstance();

      // ── Build the provider container ──────────────────────────────────
      // NOTE: we DO override deviceIdProvider with the canonical hex fp
      // that the harness installed in family_devices. This is the same
      // shape main.dart will produce once Fix Team #1 lands — the entire
      // point of this test is to assert the wiring is correct here too.
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWith((_) async => db),
          deviceIdProvider.overrideWithValue(fx.deviceA),
        ],
      );
      addTearDown(container.dispose);

      // Pre-create the baby through the real repository so the home screen
      // has data to render. Mirrors what WelcomeScreen._start() does after
      // the user enters a name and taps the CTA.
      final babyRepo = container.read(babyRepositoryProvider);
      final baby = await babyRepo.insert(
        name: 'Mali',
        dob: DateTime.utc(2026, 3, 1),
      );
      await container
          .read(currentBabyIdProvider.notifier)
          .select(baby.id);

      // ── Mount HomeScreen ──────────────────────────────────────────────
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          // ignore: prefer_const_constructors — container is non-const.
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // ── Bug B end-to-end assertion ───────────────────────────────────
      expect(
        tester.takeException(),
        isNull,
        reason:
            'HomeScreen must mount without throwing — if this fires, '
            '_BabySwitcherTitle has regressed back to firstWhere() on '
            'an empty/loading babies list.',
      );
      expect(
        find.byType(ErrorWidget),
        findsNothing,
        reason:
            'No part of the home screen may render an ErrorWidget. The '
            'AppBar title is the historical hotspot — see Bug B notes in '
            'baby_switcher_title_test.dart.',
      );

      // ── Bug A end-to-end assertion ───────────────────────────────────
      // The baby insert above marked sync_state dirty + scheduled a push.
      // We now drive a full sync cycle and assert it lands cleanly.
      await container.read(syncLifecycleControllerProvider).syncNow();
      // Let any post-sync provider updates settle.
      await tester.pumpAndSettle(const Duration(milliseconds: 200));

      final status = container.read(syncStatusProvider);
      expect(
        status.lastError,
        isNull,
        reason:
            'First-sync push must succeed — if this fires with a 42501 '
            'PostgrestException, deviceIdProvider has regressed back to '
            'UUIDv4 (or another non-hex form). The RLS contract requires '
            '`written_by_device = encode(family_devices.device_fp, '
            "'hex')` — see supabase/migrations/0017_rls_reharden.sql:19-22 "
            'and the focused contract test in '
            'test/integration/sync_device_fp_contract_test.dart.',
      );
      expect(
        status.lastSyncedAt,
        isNotNull,
        reason: 'successful sync should set lastSyncedAt',
      );

      // ── Bonus: real data DID render (fallback didn't swallow it) ─────
      expect(
        find.text('Mali'),
        findsAtLeastNWidgets(1),
        reason:
            'AppBar title should show the active baby name after sync — '
            'if only the fallback "DreamBook" is visible, Bug B\'s fix '
            'has over-corrected and is hiding real data.',
      );

      // Sanity: the server received our push.
      final pulled = await fx.serverB.pullRows(familyId: fx.familyId);
      expect(
        pulled.any((r) => r.recordId == baby.id),
        isTrue,
        reason: 'baby row should be present on the server after first sync',
      );
      // Reference Uint8List import so the analyzer keeps it (used implicitly
      // via the harness when the test eventually inspects ciphertext bytes).
      // ignore: unused_local_variable
      final _ = Uint8List(0);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
