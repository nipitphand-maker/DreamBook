import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/db/migrations/m001_initial.dart';
import 'package:dreambook/core/db/migrations/m002_v2.dart';
import 'package:dreambook/core/db/migrations/m003_v3.dart';
import 'package:dreambook/core/db/migrations/migrations.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/providers/device_id_provider.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/core/sync/sync_lifecycle_controller.dart';
import 'package:dreambook/features/baby/data/baby_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// No-op sync controller stub so v3 tests (which set `prefs['family.id']`)
/// don't trigger the production `SupabaseClientService.instance` codepath.
/// schedulePush is the only call BabyRepository.insert() makes on it.
class _StubSyncLifecycleController implements SyncLifecycleController {
  int schedulePushCalls = 0;
  @override
  void schedulePush() {
    schedulePushCalls += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('stub: ${invocation.memberName}');
}

void main() {
  setUpAll(() => sqfliteFfiInit());

  late Database db;
  late ProviderContainer container;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (d, _) async {
          await Migrations([m001Initial, m002V2]).runAll(d);
        },
      ),
    );
    await db.execute('PRAGMA foreign_keys = ON');
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((_) async => db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        deviceIdProvider.overrideWithValue('test-device-fp'),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  BabyRepository repo() => container.read(babyRepositoryProvider);

  test('insert() persists baby row with required fields', () async {
    final dob = DateTime.utc(2026, 3, 1);
    final baby = await repo().insert(
      name: 'Mali',
      nickname: 'Mali-bear',
      dob: dob,
      sex: BabySex.female,
      preferredUnit: PreferredUnit.oz,
    );

    expect(baby.name, 'Mali');
    expect(baby.nickname, 'Mali-bear');
    expect(baby.sex, BabySex.female);
    expect(baby.preferredUnit, PreferredUnit.oz);
    expect(baby.version, 1);
    expect(baby.deletedAt, isNull);

    final rows = await db.query('baby');
    expect(rows.length, 1);
    expect(rows.first['name'], 'Mali');
    expect(rows.first['nickname'], 'Mali-bear');
    expect(rows.first['sex'], 'female');
    expect(rows.first['preferred_unit'], 'oz');
    expect(rows.first['dob'], '2026-03-01');
    expect(rows.first['version'], 1);
    expect(rows.first['deleted_at'], isNull);
  });

  test('insert() generates v4 UUID for id', () async {
    final baby = await repo().insert(
      name: 'Mali',
      dob: DateTime.utc(2026, 3, 1),
    );

    // RFC 4122 v4 UUID: xxxxxxxx-xxxx-4xxx-[8-b]xxx-xxxxxxxxxxxx
    final uuidV4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    expect(uuidV4.hasMatch(baby.id), isTrue,
        reason: 'id should be a v4 UUID, got "${baby.id}"');
  });

  test('insert() writes sync_state row with dirty=1 and version=1', () async {
    final baby = await repo().insert(
      name: 'Mali',
      dob: DateTime.utc(2026, 3, 1),
    );

    final rows = await db.query(
      'sync_state',
      where: 'record_id = ? AND table_name = ?',
      whereArgs: [baby.id, 'baby'],
    );
    expect(rows.length, 1);
    expect(rows.first['dirty'], 1);
    expect(rows.first['version'], 1);
    expect(rows.first['updated_at'], isNotNull);
  });

  test('getActive() returns null when no babies exist', () async {
    final result = await repo().getActive();
    expect(result, isNull);
  });

  test(
      'getActive() returns the only baby when one exists (excludes soft-deleted)',
      () async {
    // Insert baby A (will be soft-deleted).
    final a = await repo().insert(
      name: 'Mali',
      dob: DateTime.utc(2026, 3, 1),
    );
    await repo().softDelete(a.id);

    // Insert baby B (active).
    final b = await repo().insert(
      name: 'Nara',
      dob: DateTime.utc(2026, 4, 1),
    );

    final active = await repo().getActive();
    expect(active, isNotNull);
    expect(active!.id, b.id);
    expect(active.name, 'Nara');
  });

  test('softDelete() sets deleted_at, bumps version, marks sync_state dirty',
      () async {
    final baby = await repo().insert(
      name: 'Mali',
      dob: DateTime.utc(2026, 3, 1),
    );

    // Mark sync_state clean to verify it's flipped back to dirty.
    await db.update(
      'sync_state',
      {'dirty': 0},
      where: 'record_id = ? AND table_name = ?',
      whereArgs: [baby.id, 'baby'],
    );

    await repo().softDelete(baby.id);

    final rows =
        await db.query('baby', where: 'id = ?', whereArgs: [baby.id]);
    expect(rows.length, 1);
    expect(rows.first['deleted_at'], isNotNull);
    expect(rows.first['version'], 2);

    final sync = await db.query(
      'sync_state',
      where: 'record_id = ? AND table_name = ?',
      whereArgs: [baby.id, 'baby'],
    );
    expect(sync.length, 1);
    expect(sync.first['dirty'], 1);
    expect(sync.first['version'], 2);
  });

  // ─────────────────────────────────────────────────────────────────────
  // family_id stamping (Plan C m003+)
  // ─────────────────────────────────────────────────────────────────────
  //
  // The Welcome reordering (bootstrap_family BEFORE babyRepo.insert) means
  // prefs['family.id'] is guaranteed to be set by the time insert() runs.
  // BabyRepository.insert() now stamps that family_id onto the row so
  // list()/getActive() (which filter by family_id) can find it.
  //
  // These tests run m001..m003 to add the `family_id` column that
  // production code expects post-Plan C.

  group('insert() family_id stamping (v3 schema)', () {
    late Database dbV3;
    late ProviderContainer containerV3;
    late SharedPreferences prefsV3;

    Future<void> openWithPrefs(Map<String, Object> initialPrefs) async {
      SharedPreferences.setMockInitialValues(initialPrefs);
      prefsV3 = await SharedPreferences.getInstance();
      // `singleInstance: false` is required: sqflite_common_ffi otherwise
      // pools `:memory:` opens by path, so the outer setUp's v2 db handle
      // is returned here and m003 never runs (onCreate is skipped because
      // the connection already exists at version 2).
      dbV3 = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 3,
          singleInstance: false,
          onCreate: (d, _) async {
            await Migrations([m001Initial, m002V2, m003V3]).runAll(d);
          },
        ),
      );
      await dbV3.execute('PRAGMA foreign_keys = ON');
      containerV3 = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => dbV3),
          sharedPreferencesProvider.overrideWithValue(prefsV3),
          deviceIdProvider.overrideWithValue('test-device-fp'),
          // Setting `family.id` flips currentFamilyIdProvider non-null,
          // which makes the production syncLifecycleControllerProvider try
          // to dereference SupabaseClientService.instance (uninitialised in
          // unit tests). Stub the controller to short-circuit that path.
          syncLifecycleControllerProvider
              .overrideWithValue(_StubSyncLifecycleController()),
        ],
      );
    }

    tearDown(() async {
      containerV3.dispose();
      await dbV3.close();
    });

    BabyRepository repoV3() => containerV3.read(babyRepositoryProvider);

    test(
        'case 1: prefs[family.id]=<uuid> → row.family_id equals that uuid',
        () async {
      const familyUuid = 'fffffff1-1111-4111-8111-111111111111';
      await openWithPrefs({'family.id': familyUuid});

      final baby = await repoV3().insert(
        name: 'Mali',
        dob: DateTime.utc(2026, 3, 1),
      );

      final rows = await dbV3
          .query('baby', where: 'id = ?', whereArgs: [baby.id]);
      expect(rows.length, 1);
      expect(rows.first['family_id'], familyUuid,
          reason:
              'insert() must stamp the active family_id from prefs onto the row '
              'so list()/getActive() (filtered by family_id) can find it.');
    });

    test(
        'case 2a: prefs[family.id] unset → row.family_id falls back to DDL default ""',
        () async {
      await openWithPrefs({}); // no family.id key

      final baby = await repoV3().insert(
        name: 'Mali',
        dob: DateTime.utc(2026, 3, 1),
      );

      final rows = await dbV3
          .query('baby', where: 'id = ?', whereArgs: [baby.id]);
      expect(rows.length, 1,
          reason: 'insert() must succeed even when prefs has no family.id');
      expect(rows.first['family_id'], '',
          reason:
              'When prefs.family.id is unset, repo skips the override and the '
              'DDL default kicks in. The default in m003 is "" (empty string, '
              'NOT NULL).');
    });

    test(
        'case 2b: prefs[family.id]="" → row.family_id is "" (default), not the empty string explicitly stamped',
        () async {
      await openWithPrefs({'family.id': ''});

      final baby = await repoV3().insert(
        name: 'Mali',
        dob: DateTime.utc(2026, 3, 1),
      );

      final rows = await dbV3
          .query('baby', where: 'id = ?', whereArgs: [baby.id]);
      expect(rows.length, 1);
      // Same observable outcome as 2a — `''` from prefs hits the
      // `.isNotEmpty` guard and is skipped, DDL default is `''`.
      expect(rows.first['family_id'], '',
          reason:
              'Empty-string family.id in prefs must NOT be stamped; the '
              'isNotEmpty guard skips it so the DDL default ("") applies.');
    });

    test(
        'case 3: two inserts with prefs changing between them → each row stamps the prefs value at insert time',
        () async {
      const familyA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      const familyB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

      await openWithPrefs({'family.id': familyA});

      final babyA = await repoV3().insert(
        name: 'Mali',
        dob: DateTime.utc(2026, 3, 1),
      );

      // Caregiver switches to a different family between inserts.
      await prefsV3.setString('family.id', familyB);

      final babyB = await repoV3().insert(
        name: 'Nara',
        dob: DateTime.utc(2026, 4, 1),
      );

      final rowsA = await dbV3
          .query('baby', where: 'id = ?', whereArgs: [babyA.id]);
      final rowsB = await dbV3
          .query('baby', where: 'id = ?', whereArgs: [babyB.id]);

      expect(rowsA.first['family_id'], familyA,
          reason: 'First insert must stamp the family active at THAT time.');
      expect(rowsB.first['family_id'], familyB,
          reason: 'Second insert must read prefs again and stamp the new '
              'family — repo must not cache the family_id across calls.');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // insert() / update() input validation
  // Defense-in-depth alongside TextField.maxLength on welcome_screen + add_baby
  // — so a programmatic caller can't bypass UI limits and bloat ciphertext.
  // ───────────────────────────────────────────────────────────────────────
  group('insert() input validation', () {
    test('rejects empty name (after trim)', () async {
      final repo = container.read(babyRepositoryProvider);
      await expectLater(
        repo.insert(name: '   ', dob: DateTime.utc(2026, 3, 1)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects name longer than 80 chars', () async {
      final repo = container.read(babyRepositoryProvider);
      await expectLater(
        repo.insert(name: 'x' * 81, dob: DateTime.utc(2026, 3, 1)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects nickname longer than 40 chars', () async {
      final repo = container.read(babyRepositoryProvider);
      await expectLater(
        repo.insert(
          name: 'Mali',
          nickname: 'y' * 41,
          dob: DateTime.utc(2026, 3, 1),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('trims whitespace and normalises empty nickname to null', () async {
      final repo = container.read(babyRepositoryProvider);
      final baby = await repo.insert(
        name: '  Mali  ',
        nickname: '   ',
        dob: DateTime.utc(2026, 3, 1),
      );
      expect(baby.name, 'Mali',
          reason: 'name must be trimmed before storage');
      expect(baby.nickname, isNull,
          reason: 'all-whitespace nickname must be normalised to null '
              'so it does not occupy column space');
    });

    test('accepts exactly the boundary values (80 / 40)', () async {
      final repo = container.read(babyRepositoryProvider);
      final baby = await repo.insert(
        name: 'n' * 80,
        nickname: 'k' * 40,
        dob: DateTime.utc(2026, 3, 1),
      );
      expect(baby.name.length, 80);
      expect(baby.nickname?.length, 40);
    });
  });
}
