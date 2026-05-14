import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/db/migrations/m001_initial.dart';
import 'package:dreambook/core/db/migrations/m002_v2.dart';
import 'package:dreambook/core/db/migrations/migrations.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/features/stash/data/stash_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  late Database db;
  late ProviderContainer container;
  late StashRepository repo;

  setUp(() async {
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
      ],
    );
    repo = container.read(stashRepositoryProvider);
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

  // Test 1: availableFor returns empty when no bottles
  test('availableFor returns empty when no bottles', () async {
    final bottles = await repo.availableFor('b1');
    expect(bottles, isEmpty);
  });

  // Test 2: availableFor returns only non-deleted, non-consumed, non-discarded bottles
  test(
      'availableFor returns only non-deleted, non-consumed, non-discarded bottles',
      () async {
    final pumpedAt = DateTime.utc(2026, 5, 1);

    // Normal bottle
    final normal = await repo.insertManual(
      babyId: 'b1',
      oz: 4.0,
      pumpedAt: pumpedAt,
    );

    // Deleted bottle
    final toDelete = await repo.insertManual(
      babyId: 'b1',
      oz: 3.0,
      pumpedAt: pumpedAt,
    );
    await repo.softDelete(toDelete.id, babyId: 'b1');

    // Consumed bottle
    final toConsume = await repo.insertManual(
      babyId: 'b1',
      oz: 2.0,
      pumpedAt: pumpedAt,
    );
    await repo.consume(toConsume.id, babyId: 'b1');

    // Discarded bottle
    final toDiscard = await repo.insertManual(
      babyId: 'b1',
      oz: 1.5,
      pumpedAt: pumpedAt,
    );
    await repo.discard(toDiscard.id, babyId: 'b1');

    final available = await repo.availableFor('b1');
    expect(available.length, 1);
    expect(available.first.id, normal.id);
  });

  // Test 3: availableFor orders by pumped_at ASC (oldest first)
  test('availableFor orders by pumped_at ASC (oldest first)', () async {
    final newer = await repo.insertManual(
      babyId: 'b1',
      oz: 4.0,
      pumpedAt: DateTime.utc(2026, 5, 10),
    );
    final older = await repo.insertManual(
      babyId: 'b1',
      oz: 3.0,
      pumpedAt: DateTime.utc(2026, 5, 1),
    );
    final middle = await repo.insertManual(
      babyId: 'b1',
      oz: 2.0,
      pumpedAt: DateTime.utc(2026, 5, 5),
    );

    final available = await repo.availableFor('b1');
    expect(available.length, 3);
    expect(available[0].id, older.id);
    expect(available[1].id, middle.id);
    expect(available[2].id, newer.id);
  });

  // Test 4: insertManual creates a bottle with correct fields
  test('insertManual creates a bottle with correct fields', () async {
    final pumpedAt = DateTime.utc(2026, 5, 13, 10);
    final bottle = await repo.insertManual(
      babyId: 'b1',
      oz: 4.5,
      pumpedAt: pumpedAt,
      storage: StorageType.fridge,
    );

    expect(bottle.babyId, 'b1');
    expect(bottle.oz, 4.5);
    expect(bottle.pumpedAt, pumpedAt);
    expect(bottle.storage, StorageType.fridge);
    expect(bottle.source, BottleSource.collector);
    expect(bottle.version, 1);
    expect(bottle.deletedAt, isNull);
    expect(bottle.consumedAt, isNull);
    expect(bottle.discardedAt, isNull);

    final rows = await db.query('stash_bottle', where: 'id = ?', whereArgs: [bottle.id]);
    expect(rows.length, 1);
    expect(rows.first['baby_id'], 'b1');
    expect(rows.first['oz'], 4.5);
    expect(rows.first['source'], 'collector');
    expect(rows.first['storage'], 'fridge');
  });

  // Test 5: insertManual sets expiresAt = pumpedAt + 180 days
  test('insertManual sets expiresAt = pumpedAt + 180 days', () async {
    final pumpedAt = DateTime.utc(2026, 5, 13);
    final bottle = await repo.insertManual(
      babyId: 'b1',
      oz: 3.0,
      pumpedAt: pumpedAt,
    );

    final expectedExpiry = pumpedAt.add(const Duration(days: 180));
    expect(bottle.expiresAt, expectedExpiry);

    final rows = await db.query('stash_bottle', where: 'id = ?', whereArgs: [bottle.id]);
    final storedExpiry = DateTime.parse(rows.first['expires_at']! as String);
    expect(storedExpiry, expectedExpiry);
  });

  // Test 6: insertManual writes sync_state row with dirty=1
  test('insertManual writes sync_state row with dirty=1', () async {
    final bottle = await repo.insertManual(
      babyId: 'b1',
      oz: 4.0,
      pumpedAt: DateTime.utc(2026, 5, 13),
    );

    final syncRows = await db.query(
      'sync_state',
      where: 'record_id = ? AND table_name = ?',
      whereArgs: [bottle.id, 'stash_bottle'],
    );
    expect(syncRows.length, 1);
    expect(syncRows.first['dirty'], 1);
    expect(syncRows.first['version'], 1);
  });

  // Test 7: totalOzFor returns sum of available oz
  test('totalOzFor returns sum of available oz', () async {
    await repo.insertManual(babyId: 'b1', oz: 4.0, pumpedAt: DateTime.utc(2026, 5, 1));
    await repo.insertManual(babyId: 'b1', oz: 3.5, pumpedAt: DateTime.utc(2026, 5, 2));
    await repo.insertManual(babyId: 'b1', oz: 2.0, pumpedAt: DateTime.utc(2026, 5, 3));

    final total = await repo.totalOzFor('b1');
    expect(total, closeTo(9.5, 0.001));
  });

  // Test 8: totalOzFor excludes consumed bottles
  test('totalOzFor excludes consumed bottles', () async {
    await repo.insertManual(babyId: 'b1', oz: 4.0, pumpedAt: DateTime.utc(2026, 5, 1));
    final toConsume = await repo.insertManual(
      babyId: 'b1',
      oz: 3.0,
      pumpedAt: DateTime.utc(2026, 5, 2),
    );
    await repo.consume(toConsume.id, babyId: 'b1');

    final total = await repo.totalOzFor('b1');
    expect(total, closeTo(4.0, 0.001));
  });

  // Test 9: expiringWithin returns bottles expiring within N days
  test('expiringWithin returns bottles expiring within N days', () async {
    final now = DateTime.now().toUtc();
    // Bottle expiring in 1 day (within 2 days)
    final expiringSoon = await repo.insertManual(
      babyId: 'b1',
      oz: 2.0,
      // pumpedAt such that expiresAt = pumpedAt + 180 days is ~1 day from now
      pumpedAt: now.subtract(const Duration(days: 179)),
    );
    // Bottle expiring in 5 days (NOT within 2 days)
    await repo.insertManual(
      babyId: 'b1',
      oz: 3.0,
      pumpedAt: now.subtract(const Duration(days: 175)),
    );

    final expiring = await repo.expiringWithin('b1', days: 2);
    expect(expiring.length, 1);
    expect(expiring.first.id, expiringSoon.id);
  });

  // Test 10: consume sets consumed_at + consumed_feed_id, bumps version
  test('consume sets consumed_at + consumed_feed_id, bumps version', () async {
    final bottle = await repo.insertManual(
      babyId: 'b1',
      oz: 4.0,
      pumpedAt: DateTime.utc(2026, 5, 13),
    );
    expect(bottle.version, 1);

    await repo.consume(bottle.id, babyId: 'b1', feedId: 'feed-123');

    final rows = await db.query('stash_bottle', where: 'id = ?', whereArgs: [bottle.id]);
    expect(rows.first['consumed_at'], isNotNull);
    expect(rows.first['consumed_feed_id'], 'feed-123');
    expect(rows.first['version'], 2);
  });

  // Test 11: discard sets discarded_at, bumps version
  test('discard sets discarded_at, bumps version', () async {
    final bottle = await repo.insertManual(
      babyId: 'b1',
      oz: 4.0,
      pumpedAt: DateTime.utc(2026, 5, 13),
    );
    expect(bottle.version, 1);

    await repo.discard(bottle.id, babyId: 'b1');

    final rows = await db.query('stash_bottle', where: 'id = ?', whereArgs: [bottle.id]);
    expect(rows.first['discarded_at'], isNotNull);
    expect(rows.first['version'], 2);
  });

  // Test 12: softDelete sets deleted_at, bumps version
  test('softDelete sets deleted_at, bumps version', () async {
    final bottle = await repo.insertManual(
      babyId: 'b1',
      oz: 4.0,
      pumpedAt: DateTime.utc(2026, 5, 13),
    );
    expect(bottle.version, 1);

    await repo.softDelete(bottle.id, babyId: 'b1');

    final rows = await db.query('stash_bottle', where: 'id = ?', whereArgs: [bottle.id]);
    expect(rows.first['deleted_at'], isNotNull);
    expect(rows.first['version'], 2);
  });
}
