import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Represents a bottle portion to be stashed at pump-save time.
class PendingBottle {
  const PendingBottle({required this.oz, this.source = BottleSource.pump});

  final double oz;
  final BottleSource source;
}

/// Local persistence for PumpSession + companion StashBottle creation.
///
/// All writes go through a transaction that ALSO updates the `sync_state`
/// ledger so the Plan C sync layer can find dirty rows. IDs and timestamps
/// are generated Dart-side (UTC ISO-8601 + v4 UUID) — never relying on
/// SQLite's clock.
///
/// Note: `total_oz` is a VIRTUAL GENERATED column — never included in INSERT.
class PumpRepository {
  PumpRepository(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  Future<Database> get _db => _ref.read(appDatabaseProvider.future);

  /// All non-deleted pump sessions for [babyId] that started on or after
  /// midnight UTC of [now] (defaults to `DateTime.now()`). Ordered by
  /// `started_at DESC` — freshest session first.
  Future<List<PumpSession>> todayFor(String babyId, {DateTime? now}) async {
    final db = await _db;
    final n = (now ?? DateTime.now()).toUtc();
    final startOfDay = DateTime.utc(n.year, n.month, n.day).toIso8601String();
    final rows = await db.query(
      'pump_session',
      where: 'baby_id = ? AND deleted_at IS NULL AND started_at >= ?',
      whereArgs: [babyId, startOfDay],
      orderBy: 'started_at DESC',
    );
    return rows.map(PumpSession.fromRow).toList(growable: false);
  }

  /// Insert a new PumpSession row atomically with optional StashBottle rows.
  ///
  /// For each [PendingBottle] in [bottles]:
  /// - `pumpedAt = startedAt`
  /// - `frozenAt = startedAt`
  /// - `expiresAt = startedAt + 180 days` (CDC 6-month freezer guideline)
  /// - `storage = StorageType.freezer`
  ///
  /// Creates one `sync_state` row per entity (1 + N total).
  /// Invalidates [pumpTodayProvider] for [babyId] on success.
  Future<PumpSession> insert({
    required String babyId,
    required DateTime startedAt,
    DateTime? endedAt,
    double leftOz = 0,
    double rightOz = 0,
    int? durationMin,
    int pausedDurationMin = 0,
    String? note,
    String? loggedBy,
    List<PendingBottle> bottles = const [],
  }) async {
    final db = await _db;
    final now = DateTime.now().toUtc();
    final session = PumpSession(
      id: _uuid.v4(),
      babyId: babyId,
      leftOz: leftOz,
      rightOz: rightOz,
      durationMin: durationMin,
      pausedDurationMin: pausedDurationMin,
      startedAt: startedAt.toUtc(),
      endedAt: endedAt?.toUtc(),
      note: note,
      loggedBy: loggedBy,
      createdAt: now,
      updatedAt: now,
    );

    // Build StashBottle objects for each pending bottle
    final stashBottles = bottles.map((b) {
      final pumpedAtUtc = startedAt.toUtc();
      return StashBottle(
        id: _uuid.v4(),
        babyId: babyId,
        pumpSessionId: session.id,
        oz: b.oz,
        pumpedAt: pumpedAtUtc,
        frozenAt: pumpedAtUtc,
        expiresAt: pumpedAtUtc.add(const Duration(days: 180)),
        storage: StorageType.freezer,
        source: b.source,
        createdAt: now,
        updatedAt: now,
      );
    }).toList(growable: false);

    await db.transaction((txn) async {
      // Insert pump_session
      await txn.insert('pump_session', session.toRow());
      await txn.insert(
        'sync_state',
        {
          'record_id': session.id,
          'table_name': 'pump_session',
          'version': session.version,
          'updated_at': now.toIso8601String(),
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Insert each stash bottle
      for (final bottle in stashBottles) {
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
      }
    });

    _ref.invalidate(pumpTodayProvider(babyId));
    return session;
  }

  /// Soft-delete: stamps `deleted_at`, bumps version, marks `sync_state` dirty.
  ///
  /// Does NOT cascade-delete companion stash_bottles — the milk physically
  /// exists in the freezer and must be managed separately via StashRepository.
  ///
  /// No-op if [id] does not exist (zero rows updated).
  Future<void> softDelete(String id, {required String babyId}) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      final affected = await txn.rawUpdate(
        '''
        UPDATE pump_session
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
              'SELECT version FROM pump_session WHERE id = ?',
              [id],
            ),
          ) ??
          1;

      await txn.insert(
        'sync_state',
        {
          'record_id': id,
          'table_name': 'pump_session',
          'version': newVersion,
          'updated_at': now,
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _ref.invalidate(pumpTodayProvider(babyId));
  }
}

final pumpRepositoryProvider =
    Provider<PumpRepository>(PumpRepository.new);

/// Today's pump sessions for the given `babyId`, ordered `started_at DESC`,
/// excluding soft-deleted. Invalidated by every [PumpRepository] write.
///
/// Riverpod 3 dropped the `FamilyAsyncNotifier` subclass — family notifiers
/// are now just `AsyncNotifier`s constructed per-arg, with the arg held on
/// the instance.
final pumpTodayProvider =
    AsyncNotifierProvider.family<PumpTodayNotifier, List<PumpSession>, String>(
  PumpTodayNotifier.new,
);

class PumpTodayNotifier extends AsyncNotifier<List<PumpSession>> {
  PumpTodayNotifier(this.babyId);

  final String babyId;

  @override
  Future<List<PumpSession>> build() =>
      ref.read(pumpRepositoryProvider).todayFor(babyId);
}
