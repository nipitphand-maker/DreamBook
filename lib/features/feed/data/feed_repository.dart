import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/sync/sync_lifecycle_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Thrown by [FeedRepository.update] when the row's version in the database
/// does not match the snapshot version the caller is trying to write — i.e.
/// another writer (or another tab/caregiver) committed first.
///
/// Plan C will use this to fall back to a merge prompt. Plan B just surfaces
/// the conflict so the UI can re-fetch and retry.
class ConcurrentUpdateException implements Exception {
  ConcurrentUpdateException(this.table, this.id);

  final String table;
  final String id;

  @override
  String toString() =>
      'ConcurrentUpdateException($table:$id) — version mismatch';
}

/// Local persistence for the Feed entity.
///
/// All writes go through a transaction that ALSO updates the `sync_state`
/// ledger so the Plan C sync layer can find dirty rows. IDs and timestamps
/// are generated Dart-side (UTC ISO-8601 + v4 UUID) — never relying on
/// SQLite's clock.
class FeedRepository {
  FeedRepository(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  Future<Database> get _db => _ref.read(appDatabaseProvider.future);

  /// All non-deleted feeds for [babyId] that started on or after midnight UTC
  /// of [now] (defaults to `DateTime.now()`). Ordered by `started_at DESC` —
  /// freshest feed first, the way the Home "Today" row reads it.
  Future<List<Feed>> todayFor(String babyId, {DateTime? now}) async {
    final db = await _db;
    final n = (now ?? DateTime.now()).toUtc();
    final startOfDay = DateTime.utc(n.year, n.month, n.day).toIso8601String();
    final rows = await db.query(
      'feed',
      where: 'baby_id = ? AND deleted_at IS NULL AND started_at >= ?',
      whereArgs: [babyId, startOfDay],
      orderBy: 'started_at DESC',
    );
    return rows.map(Feed.fromRow).toList(growable: false);
  }

  /// Insert a new Feed row. Generates v4 UUID + timestamps Dart-side.
  /// Touches `sync_state` in the same transaction with `dirty=1`.
  ///
  /// Invalidates [feedTodayProvider] for [babyId] on success so any open
  /// timeline rebuilds.
  Future<Feed> insert({
    required String babyId,
    required FeedType type,
    FeedSide? side,
    double? oz,
    FeedSource? source,
    String? fromStashBottleId,
    required DateTime startedAt,
    DateTime? endedAt,
    String? note,
    String? loggedBy,
  }) async {
    final db = await _db;
    final now = DateTime.now().toUtc();
    final feed = Feed(
      id: _uuid.v4(),
      babyId: babyId,
      type: type,
      side: side,
      oz: oz,
      source: source,
      fromStashBottleId: fromStashBottleId,
      startedAt: startedAt.toUtc(),
      endedAt: endedAt?.toUtc(),
      note: note,
      loggedBy: loggedBy,
      createdAt: now,
      updatedAt: now,
    );

    await db.transaction((txn) async {
      await txn.insert('feed', feed.toRow());
      await txn.insert(
        'sync_state',
        {
          'record_id': feed.id,
          'table_name': 'feed',
          'version': feed.version,
          'updated_at': now.toIso8601String(),
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _ref.invalidate(feedTodayProvider(babyId));
    _ref.read(syncLifecycleControllerProvider).schedulePush();
    return feed;
  }

  /// Optimistic-concurrency update: writes [updated] only when the row's
  /// current `version` matches `updated.version`. Bumps version by 1 and
  /// stamps `updated_at = now-utc`.
  ///
  /// Throws [ConcurrentUpdateException] if the WHERE clause matches zero
  /// rows (another writer beat us, or the row is gone).
  Future<Feed> update(Feed updated) async {
    final db = await _db;
    final now = DateTime.now().toUtc();
    final nextVersion = updated.version + 1;
    final next = updated.copyWith(version: nextVersion, updatedAt: now);

    await db.transaction((txn) async {
      final rows = await txn.update(
        'feed',
        next.toRow(),
        where: 'id = ? AND version = ?',
        whereArgs: [next.id, updated.version],
      );
      if (rows == 0) {
        throw ConcurrentUpdateException('feed', next.id);
      }
      await txn.insert(
        'sync_state',
        {
          'record_id': next.id,
          'table_name': 'feed',
          'version': nextVersion,
          'updated_at': now.toIso8601String(),
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _ref.invalidate(feedTodayProvider(next.babyId));
    _ref.read(syncLifecycleControllerProvider).schedulePush();
    return next;
  }

  /// Soft-delete: stamps `deleted_at`, bumps version, marks `sync_state` dirty.
  /// No-op if [id] does not exist (zero rows updated).
  Future<void> softDelete(String id, {required String babyId}) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      final affected = await txn.rawUpdate(
        '''
        UPDATE feed
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
              'SELECT version FROM feed WHERE id = ?',
              [id],
            ),
          ) ??
          1;

      await txn.insert(
        'sync_state',
        {
          'record_id': id,
          'table_name': 'feed',
          'version': newVersion,
          'updated_at': now,
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _ref.invalidate(feedTodayProvider(babyId));
    _ref.read(syncLifecycleControllerProvider).schedulePush();
  }
}

final feedRepositoryProvider =
    Provider<FeedRepository>(FeedRepository.new);

/// Today's feeds for the given `babyId`, ordered `started_at DESC`,
/// excluding soft-deleted. Invalidated by every [FeedRepository] write.
///
/// Riverpod 3 dropped the `FamilyAsyncNotifier` subclass — family notifiers
/// are now just `AsyncNotifier`s constructed per-arg, with the arg held on
/// the instance.
final feedTodayProvider =
    AsyncNotifierProvider.family<FeedTodayNotifier, List<Feed>, String>(
  FeedTodayNotifier.new,
);

class FeedTodayNotifier extends AsyncNotifier<List<Feed>> {
  FeedTodayNotifier(this.babyId);

  final String babyId;

  @override
  Future<List<Feed>> build() {
    final repo = ref.read(feedRepositoryProvider);
    return repo.todayFor(babyId);
  }
}
