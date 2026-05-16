import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/db/migrations/m001_initial.dart';
import 'package:dreambook/core/db/migrations/m002_v2.dart';
import 'package:dreambook/core/db/migrations/migrations.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/providers/device_id_provider.dart';
import 'package:dreambook/core/providers/premium_provider.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/core/providers/stash_expiry_settings_provider.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/features/stash/data/stash_repository.dart';
import 'package:dreambook/features/stash/presentation/stash_list_screen.dart';
import 'package:dreambook/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ---------------------------------------------------------------------------
// Fake notifier for synchronous bottle injection
// ---------------------------------------------------------------------------

/// Injects a fixed list of bottles synchronously — bypasses the FFI SQLite
/// isolate, which does not pump inside FakeAsync (→ pumpAndSettle times out).
class _FixedStashNotifier extends StashAvailableNotifier {
  _FixedStashNotifier(this._bottles) : super('b1');
  final List<StashBottle> _bottles;

  @override
  Future<List<StashBottle>> build() async => _bottles;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wraps the screen with the minimum provider overrides needed by the UI.
///
/// [bottles] is injected via [_FixedStashNotifier] so we avoid dispatching
/// real SQLite queries through the background-isolate FFI driver (which does
/// not pump inside FakeAsync → pumpAndSettle times out). A minimal in-memory
/// DB is still provided so any non-bottleList reads have a valid handle.
Widget _wrapScreen({
  required SharedPreferences prefs,
  required List<StashBottle> bottles,
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWith((_) async {
        final db = await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: 2,
            onCreate: (d, _) async {
              await Migrations([m001Initial, m002V2]).runAll(d);
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
        return db;
      }),
      deviceIdProvider.overrideWithValue('test-device-fp'),
      isPremiumProvider.overrideWith((_) async => false),
      stashExpirySettingsProvider.overrideWith(
        () => StashExpirySettingsNotifier(),
      ),
      // Inject bottles synchronously — bypasses the FFI isolate entirely.
      stashAvailableProvider('b1').overrideWith(
        () => _FixedStashNotifier(bottles),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const StashListScreen(),
    ),
  );
}

/// Returns the `Border.left.color` of the tile keyed `stash_tile_$bottleId`.
/// Returns `Colors.transparent` (matches the fresh-state placeholder) when
/// the tile has no colored edge.
Color _borderLeftColor(WidgetTester tester, String bottleId) {
  final container = tester.widget<Container>(
    find.byKey(Key('stash_tile_$bottleId')),
  );
  final decoration = container.decoration! as BoxDecoration;
  final border = decoration.border! as Border;
  return border.left.color;
}

/// Builds a minimal [StashBottle] for testing.
StashBottle _bottle({
  required String id,
  required DateTime pumpedAt,
  required DateTime expiresAt,
  double oz = 4.0,
}) {
  final now = DateTime.now().toUtc();
  return StashBottle(
    id: id,
    babyId: 'b1',
    oz: oz,
    pumpedAt: pumpedAt,
    expiresAt: expiresAt,
    storage: StorageType.freezer,
    source: BottleSource.collector,
    createdAt: now,
    updatedAt: now,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() => sqfliteFfiInit());

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'current_baby_id': 'b1'});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets(
      'each tile draws the correct border-left color for its freshness state',
      (tester) async {
    final now = DateTime.now().toUtc();

    // Expired: expires 1 day ago.
    // total shelf life = 180 days; already past expiry.
    final expiredExpiry = now.subtract(const Duration(days: 1));
    final expiredPumped = expiredExpiry.subtract(const Duration(days: 180));
    final expiredBottle = _bottle(
      id: 'expired',
      pumpedAt: expiredPumped,
      expiresAt: expiredExpiry,
    );

    // Warning: ~15% remaining.
    // For a 180-day shelf life, 15% ≈ 27 days left.
    // pumpedAt = 153 days ago, expiresAt = 27 days from now.
    final warningExpiry = now.add(const Duration(days: 27));
    final warningPumped = warningExpiry.subtract(const Duration(days: 180));
    final warningBottle = _bottle(
      id: 'warning',
      pumpedAt: warningPumped,
      expiresAt: warningExpiry,
      oz: 3.0,
    );

    // Critical: ~5% remaining.
    // For a 180-day shelf life, 5% ≈ 9 days left.
    // pumpedAt = 171 days ago, expiresAt = 9 days from now.
    final criticalExpiry = now.add(const Duration(days: 9));
    final criticalPumped = criticalExpiry.subtract(const Duration(days: 180));
    final criticalBottle = _bottle(
      id: 'critical',
      pumpedAt: criticalPumped,
      expiresAt: criticalExpiry,
      oz: 2.5,
    );

    // Fresh: expires in 60 days (~33% remaining on 180-day shelf life).
    final freshExpiry = now.add(const Duration(days: 60));
    final freshPumped = freshExpiry.subtract(const Duration(days: 180));
    final freshBottle = _bottle(
      id: 'fresh',
      pumpedAt: freshPumped,
      expiresAt: freshExpiry,
      oz: 2.0,
    );

    // Inject as synchronous AsyncData — sorted by expires_at ASC (matching
    // the repository order: expired → critical → warning → fresh).
    final bottles = [expiredBottle, criticalBottle, warningBottle, freshBottle];

    await tester.pumpWidget(_wrapScreen(prefs: prefs, bottles: bottles));
    // Two pumps: first starts the async build(), second resolves the Future.
    await tester.pump();
    await tester.pump();

    // Each tile is identified by Key so assertion is order-independent.
    expect(_borderLeftColor(tester, 'expired'), AppColors.lightError);
    expect(_borderLeftColor(tester, 'critical'), AppColors.lightError);
    expect(_borderLeftColor(tester, 'warning'), AppColors.honey700);
    // Fresh = no accent → placeholder transparent border (keeps layout
    // alignment with the other tiles).
    expect(_borderLeftColor(tester, 'fresh'), Colors.transparent);
  });

  testWidgets('current_baby_id NotifierProvider drives babyId selection',
      (tester) async {
    // Sanity check that the screen renders without crashing when the
    // baby is selected via SharedPreferences (no need to override the
    // currentBabyIdProvider directly).
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(const Duration(days: 180));
    final pumpedAt = now;
    final bottle = _bottle(id: 'only', pumpedAt: pumpedAt, expiresAt: expiresAt);

    await tester.pumpWidget(_wrapScreen(prefs: prefs, bottles: [bottle]));
    await tester.pump();
    await tester.pump();

    // currentBabyIdProvider should have read 'b1' from SharedPreferences,
    // so the screen renders the list (not the no-baby placeholder).
    expect(find.byKey(const Key('stash_tile_only')), findsOneWidget);
  });
}
