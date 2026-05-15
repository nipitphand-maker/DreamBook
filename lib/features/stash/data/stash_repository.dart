import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/sync/sync_lifecycle_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Local persistence for StashBottle — manage, mark consumed / discarded,
/// soft-delete, and manually add collector bottles.
///
/// All writes go through a transaction that ALSO updates the `sync_state`
/// ledger so the Plan C sync layer can find dirty rows. IDs and timestamps
/// are generated Dart-side (UTC ISO-8601 + v4 UUID) — never relying on
/// SQLite's clock.
class StashRepository {
  StashRepository(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  Future<Database> get _db => _ref.read(appDatabaseProvider.future);

  /// All non-deleted, non-consumed, non-discarded bottles for [babyId],
  /// ordered `pumped_at ASC` (FIFO — oldest milk first).
  Future<List<StashBottle>> availableFor(String babyId) async {
    final db = await _db;
    final rows = await db.query(
      'stash_bottle',
      where:
          'deleted_at IS NULL AND consumed_at IS NULL AND discarded_at IS NULL AND baby_id = ?',
      whereArgs: [babyId],
      orderBy: 'pumped_at ASC',
    );
    return rows.map(StashBottle.fromRow).toList(growable: false);
  }

  /// Sum of [oz] for all available bottles for [babyId].
  Future<double> totalOzFor(String babyId) async {
    final bottles = await availableFor(babyId);
    return bottles.fold<double>(0, (sum, b) => sum + b.oz);
  }

  /// Available bottles where [expiresAt] <= now + [days].
  Future<List<StashBottle>> expiringWithin(
    String babyId, {
    int days = 2,
  }) async {
    final bottles = await availableFor(babyId);
    final cutoff = DateTime.now().add(Duration(days: days));
    return bottles.where((b) => b.expiresAt.isBefore(cutoff)).toList();
  }

  /// Manually add a collector bottle (not from a pump session).
  ///
  /// Sets [source] = [BottleSource.collector], [expiresAt] = [pumpedAt] + 180 days.
  /// Writes a `sync_state` row (dirty=1).
  /// Invalidates [stashAvailableProvider] for [babyId].
  Future<StashBottle> insertManual({
    required String babyId,
    required double oz,
    required DateTime pumpedAt,
    StorageType storage = StorageType.freezer,
    String? note,
  }) async {
    final db = await _db;
    final now = DateTime.now().toUtc();
    final pumpedAtUtc = pumpedAt.toUtc();

    final bottle = StashBottle(
      id: _uuid.v4(),
      babyId: babyId,
      oz: oz,
      pumpedAt: pumpedAtUtc,
      expiresAt: pumpedAtUtc.add(const Duration(days: 180)),
      storage: storage,
      source: BottleSource.collector,
      createdAt: now,
      updatedAt: now,
    );

    await db.transaction((txn) async {
      await txn.insert('stash_bottle', bottle.toRow());
      await txn.insert(
        'sync_state',
        {
          'record_id': bottle.id,
          'table_name': 'stash_bottle',
          'version': bottle.version,
          'updated_at': now.toIso8601String(),
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _ref.invalidate(stashAvailableProvider(babyId));
    _ref.read(syncLifecycleControllerProvider).schedulePush();
    return bottle;
  }

  /// Mark a bottle as consumed: sets [consumedAt] = now, [consumedFeedId],
  /// bumps [version], updates `sync_state`.
  /// Invalidates [stashAvailableProvider] for [babyId].
  Future<void> consume(
    String id, {
    required String babyId,
    String? feedId,
  }) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      final affected = await txn.rawUpdate(
        '''
        UPDATE stash_bottle
        SET consumed_at      = ?,
            consumed_feed_id = ?,
            updated_at       = ?,
            version          = version + 1
        WHERE id = ?
        ''',
        [now, feedId, now, id],
      );
      if (affected == 0) return;

      final newVersion = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT version FROM stash_bottle WHERE id = ?',
              [id],
            ),
          ) ??
          1;

      await txn.insert(
        'sync_state',
        {
          'record_id': id,
          'table_name': 'stash_bottle',
          'version': newVersion,
          'updated_at': now,
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _ref.invalidate(stashAvailableProvider(babyId));
    _ref.read(syncLifecycleControllerProvider).schedulePush();
  }

  /// Mark a bottle as discarded: sets [discardedAt] = now, bumps [version],
  /// updates `sync_state`.
  /// Invalidates [stashAvailableProvider] for [babyId].
  Future<void> discard(String id, {required String babyId}) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      final affected = await txn.rawUpdate(
        '''
        UPDATE stash_bottle
        SET discarded_at = ?,
            updated_at   = ?,
            version      = version + 1
        WHERE id = ?
        ''',
        [now, now, id],
      );
      if (affected == 0) return;

      final newVersion = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT version FROM stash_bottle WHERE id = ?',
              [id],
            ),
          ) ??
          1;

      await txn.insert(
        'sync_state',
        {
          'record_id': id,
          'table_name': 'stash_bottle',
          'version': newVersion,
          'updated_at': now,
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _ref.invalidate(stashAvailableProvider(babyId));
    _ref.read(syncLifecycleControllerProvider).schedulePush();
  }

  /// Soft-delete a bottle: sets [deletedAt] = now, bumps [version],
  /// updates `sync_state`.
  /// Invalidates [stashAvailableProvider] for [babyId].
  Future<void> softDelete(String id, {required String babyId}) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      final affected = await txn.rawUpdate(
        '''
        UPDATE stash_bottle
        SET deleted_at = ?,
            updated_at = ?,
            version    = version + 1
        WHERE id = ?
        ''',
        [now, now, id],
      );
      if (affected == 0) return;

      final newVersion = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT version FROM stash_bottle WHERE id = ?',
              [id],
            ),
          ) ??
          1;

      await txn.insert(
        'sync_state',
        {
          'record_id': id,
          'table_name': 'stash_bottle',
          'version': newVersion,
          'updated_at': now,
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _ref.invalidate(stashAvailableProvider(babyId));
    _ref.read(syncLifecycleControllerProvider).schedulePush();
  }
}

final stashRepositoryProvider =
    Provider<StashRepository>(StashRepository.new);

/// All available stash bottles for [babyId], FIFO ordered (oldest first).
/// Invalidated by every [StashRepository] write.
final stashAvailableProvider = AsyncNotifierProvider.family<
    StashAvailableNotifier, List<StashBottle>, String>(
  StashAvailableNotifier.new,
);

class StashAvailableNotifier extends AsyncNotifier<List<StashBottle>> {
  StashAvailableNotifier(this.babyId);
  final String babyId;

  @override
  Future<List<StashBottle>> build() =>
      ref.read(stashRepositoryProvider).availableFor(babyId);
}
