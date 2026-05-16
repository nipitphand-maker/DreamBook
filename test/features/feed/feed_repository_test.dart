import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/db/migrations/m001_initial.dart';
import 'package:dreambook/core/db/migrations/m002_v2.dart';
import 'package:dreambook/core/db/migrations/migrations.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/providers/device_id_provider.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/features/feed/data/feed_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  late Database db;
  late ProviderContainer container;
  late FeedRepository repo;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'feed.alertEnabled': false});
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
    repo = container.read(feedRepositoryProvider);
    // Insert a baby for FK satisfaction.
    await db.insert('baby', {
      'id': 'b1',
      'name': 'Mali',
      'dob': '2026-03-01',
      'preferred_unit': 'oz',
      'created_at': '2026-05-13T00:00:00.000Z',
      'updated_at': '2026-05-13T00:00:00.000Z',
      'version': 1,
    });
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('insert() persists feed row with required fields', () async {
    final startedAt = DateTime.utc(2026, 5, 13, 10);
    final feed = await repo.insert(
      babyId: 'b1',
      type: FeedType.bottle,
      side: FeedSide.left,
      oz: 4.5,
      source: FeedSource.breastmilk,
      startedAt: startedAt,
      note: 'morning feed',
      loggedBy: null,
    );

    expect(feed.babyId, 'b1');
    expect(feed.type, FeedType.bottle);
    expect(feed.side, FeedSide.left);
    expect(feed.oz, 4.5);
    expect(feed.source, FeedSource.breastmilk);
    expect(feed.note, 'morning feed');
    expect(feed.version, 1);
    expect(feed.deletedAt, isNull);

    final rows = await db.query('feed');
    expect(rows.length, 1);
    expect(rows.first['baby_id'], 'b1');
    expect(rows.first['type'], 'bottle');
    expect(rows.first['side'], 'left');
    expect(rows.first['oz'], 4.5);
    expect(rows.first['source'], 'breastmilk');
    expect(rows.first['note'], 'morning feed');
    expect(rows.first['version'], 1);
    expect(rows.first['deleted_at'], isNull);
  });

  test('insert() generates v4 UUID for id', () async {
    final feed = await repo.insert(
      babyId: 'b1',
      type: FeedType.breast,
      startedAt: DateTime.utc(2026, 5, 13, 10),
    );

    // RFC 4122 v4 UUID: xxxxxxxx-xxxx-4xxx-[8-b]xxx-xxxxxxxxxxxx
    final uuidV4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    expect(uuidV4.hasMatch(feed.id), isTrue,
        reason: 'id should be a v4 UUID, got "${feed.id}"');
  });

  test('insert() sets created_at = updated_at = ~now-utc', () async {
    final before = DateTime.now().toUtc();
    final feed = await repo.insert(
      babyId: 'b1',
      type: FeedType.breast,
      startedAt: DateTime.utc(2026, 5, 13, 10),
    );
    final after = DateTime.now().toUtc();

    expect(feed.createdAt, feed.updatedAt,
        reason: 'created_at and updated_at must match on insert');
    expect(feed.createdAt.isAtSameMomentAs(before) ||
            feed.createdAt.isAfter(before),
        isTrue);
    expect(feed.createdAt.isAtSameMomentAs(after) ||
            feed.createdAt.isBefore(after),
        isTrue);
    expect(feed.createdAt.isUtc, isTrue);
  });

  test('insert() writes sync_state row with dirty=1 and version=1', () async {
    final feed = await repo.insert(
      babyId: 'b1',
      type: FeedType.breast,
      startedAt: DateTime.utc(2026, 5, 13, 10),
    );

    final rows = await db.query(
      'sync_state',
      where: 'record_id = ? AND table_name = ?',
      whereArgs: [feed.id, 'feed'],
    );
    expect(rows.length, 1);
    expect(rows.first['dirty'], 1);
    expect(rows.first['version'], 1);
    expect(rows.first['updated_at'], isNotNull);
  });

  test(
      'todayFor(babyId) returns only rows with started_at >= today-midnight-UTC',
      () async {
    final now = DateTime.utc(2026, 5, 13, 14);
    final todayMidnight = DateTime.utc(2026, 5, 13);
    final yesterday = todayMidnight.subtract(const Duration(hours: 5));
    final todayMorning = todayMidnight.add(const Duration(hours: 6));
    final todayAfternoon = todayMidnight.add(const Duration(hours: 13));

    // Yesterday — must be excluded.
    await repo.insert(
      babyId: 'b1',
      type: FeedType.breast,
      startedAt: yesterday,
    );
    // Today morning.
    final aMorning = await repo.insert(
      babyId: 'b1',
      type: FeedType.breast,
      startedAt: todayMorning,
    );
    // Today afternoon.
    final anAfternoon = await repo.insert(
      babyId: 'b1',
      type: FeedType.bottle,
      oz: 4.0,
      startedAt: todayAfternoon,
    );

    final today = await repo.todayFor('b1', now: now);
    expect(today.length, 2);
    // started_at DESC: afternoon then morning.
    expect(today[0].id, anAfternoon.id);
    expect(today[1].id, aMorning.id);
  });

  test('todayFor(babyId) excludes soft-deleted rows', () async {
    final now = DateTime.utc(2026, 5, 13, 14);
    final todayMorning = DateTime.utc(2026, 5, 13, 6);
    final todayAfternoon = DateTime.utc(2026, 5, 13, 13);

    final morningFeed = await repo.insert(
      babyId: 'b1',
      type: FeedType.breast,
      startedAt: todayMorning,
    );
    final afternoonFeed = await repo.insert(
      babyId: 'b1',
      type: FeedType.bottle,
      oz: 4.0,
      startedAt: todayAfternoon,
    );

    await repo.softDelete(morningFeed.id, babyId: 'b1');

    final today = await repo.todayFor('b1', now: now);
    expect(today.length, 1);
    expect(today.first.id, afternoonFeed.id);
  });

  test('update() bumps version by exactly 1 and updates updated_at', () async {
    final original = await repo.insert(
      babyId: 'b1',
      type: FeedType.bottle,
      oz: 4.0,
      startedAt: DateTime.utc(2026, 5, 13, 10),
    );
    expect(original.version, 1);

    // Sleep 2ms to guarantee a different updated_at timestamp.
    await Future<void>.delayed(const Duration(milliseconds: 2));

    final edited = original.copyWith(oz: 5.0, note: 'topped up');
    final updated = await repo.update(edited);

    expect(updated.version, 2);
    expect(updated.oz, 5.0);
    expect(updated.note, 'topped up');
    expect(updated.updatedAt.isAfter(original.updatedAt), isTrue);

    final rows = await db.query('feed', where: 'id = ?', whereArgs: [original.id]);
    expect(rows.length, 1);
    expect(rows.first['version'], 2);
    expect(rows.first['oz'], 5.0);
    expect(rows.first['note'], 'topped up');
  });

  test('update() throws ConcurrentUpdateException when version mismatches',
      () async {
    final original = await repo.insert(
      babyId: 'b1',
      type: FeedType.bottle,
      oz: 4.0,
      startedAt: DateTime.utc(2026, 5, 13, 10),
    );

    // First update succeeds: 1 → 2.
    await repo.update(original.copyWith(oz: 5.0));

    // Second update with a stale snapshot (version=1) must fail.
    expect(
      () => repo.update(original.copyWith(oz: 6.0)),
      throwsA(isA<ConcurrentUpdateException>()),
    );

    // Row should not have been mutated by the failed attempt.
    final rows =
        await db.query('feed', where: 'id = ?', whereArgs: [original.id]);
    expect(rows.first['oz'], 5.0);
    expect(rows.first['version'], 2);
  });

  test('softDelete() sets deleted_at, bumps version, marks sync_state dirty',
      () async {
    final feed = await repo.insert(
      babyId: 'b1',
      type: FeedType.bottle,
      oz: 4.0,
      startedAt: DateTime.utc(2026, 5, 13, 10),
    );

    // Flip dirty=0 to verify softDelete flips it back to 1.
    await db.update(
      'sync_state',
      {'dirty': 0},
      where: 'record_id = ? AND table_name = ?',
      whereArgs: [feed.id, 'feed'],
    );

    await repo.softDelete(feed.id, babyId: 'b1');

    final rows = await db.query('feed', where: 'id = ?', whereArgs: [feed.id]);
    expect(rows.length, 1);
    expect(rows.first['deleted_at'], isNotNull);
    expect(rows.first['version'], 2);

    final sync = await db.query(
      'sync_state',
      where: 'record_id = ? AND table_name = ?',
      whereArgs: [feed.id, 'feed'],
    );
    expect(sync.length, 1);
    expect(sync.first['dirty'], 1);
    expect(sync.first['version'], 2);
  });

  test('insert with bad babyId rolls back atomically (sync_state stays empty)',
      () async {
    expect(
      () => repo.insert(
        babyId: 'non-existent-baby',
        type: FeedType.bottle,
        oz: 4.0,
        startedAt: DateTime.utc(2026, 5, 13, 10),
      ),
      throwsA(isA<DatabaseException>()),
    );

    // Both feed AND sync_state rows must be absent — the transaction
    // rolled back atomically when the FK constraint fired.
    final feedRows = await db.query('feed');
    expect(feedRows, isEmpty,
        reason: 'feed insert must roll back on FK violation');

    final syncRows = await db.query(
      'sync_state',
      where: 'table_name = ?',
      whereArgs: ['feed'],
    );
    expect(syncRows, isEmpty,
        reason: 'sync_state must not contain orphan rows after rollback');
  });
}
