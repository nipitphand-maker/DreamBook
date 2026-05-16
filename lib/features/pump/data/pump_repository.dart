import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/providers/day_start_hour_provider.dart';
import 'package:dreambook/core/sync/sync_lifecycle_controller.dart';
import 'package:dreambook/core/utils/day_boundary.dart';
import 'package:dreambook/features/stash/data/stash_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Represents a bottle portion to be stashed at pump-save time.
class PendingBottle {
  const PendingBottle({
    required this.oz,
    this.source = BottleSource.pump,
    this.storage = StorageType.freezer,
  });

  final double oz;
  final BottleSource source;
  final StorageType storage;
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

  /// All non-deleted pump sessions for [babyId] that fall within the logical
  /// day containing [now] (defaults to `DateTime.now()`), as defined by
  /// [dayStartHour]. Sessions started before [dayStartHour] are attributed to
  /// the previous calendar day. Ordered by `started_at DESC` — freshest first.
  ///
  /// [dayStartHour] defaults to 0 (midnight) for backward compatibility.
  Future<List<PumpSession>> todayFor(
    String babyId, {
    DateTime? now,
    int dayStartHour = 0,
  }) async {
    final db = await _db;
    final n = now ?? DateTime.now();
    final start = currentLogicalDayStart(n, dayStartHour);
    final end = start.add(const Duration(days: 1));
    final startStr = start.toUtc().toIso8601String();
    final endStr = end.toUtc().toIso8601String();
    final rows = await db.query(
      'pump_session',
      where:
          'baby_id = ? AND deleted_at IS NULL AND started_at >= ? AND started_at < ?',
      whereArgs: [babyId, startStr, endStr],
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
        storage: b.storage,
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
    if (bottles.isNotEmpty) {
      _ref.invalidate(stashAvailableProvider(babyId));
    }
    _ref.read(syncLifecycleControllerProvider).schedulePush();
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
    _ref.read(syncLifecycleControllerProvider).schedulePush();
  }

  /// Update mutable fields on an existing PumpSession. Bumps version, writes
  /// sync_state dirty. Throws [StateError] if [session.id] does not exist.
  ///
  /// Invalidates [pumpTodayProvider] for [session.babyId] on success.
  Future<void> update(PumpSession session) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      final affected = await txn.rawUpdate(
        '''
        UPDATE pump_session
        SET started_at          = ?,
            left_oz             = ?,
            right_oz            = ?,
            note                = ?,
            updated_at          = ?,
            version             = version + 1
        WHERE id = ? AND deleted_at IS NULL
        ''',
        [
          session.startedAt.toUtc().toIso8601String(),
          session.leftOz,
          session.rightOz,
          session.note,
          now,
          session.id,
        ],
      );
      if (affected == 0) {
        throw StateError('PumpSession ${session.id} not found or already deleted');
      }

      final newVersion = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT version FROM pump_session WHERE id = ?',
              [session.id],
            ),
          ) ??
          1;

      await txn.insert(
        'sync_state',
        {
          'record_id': session.id,
          'table_name': 'pump_session',
          'version': newVersion,
          'updated_at': now,
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _ref.invalidate(pumpTodayProvider(session.babyId));
    _ref.read(syncLifecycleControllerProvider).schedulePush();
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
  Future<List<PumpSession>> build() {
    final dayStartHour = ref.watch(dayStartHourProvider);
    return ref
        .read(pumpRepositoryProvider)
        .todayFor(babyId, dayStartHour: dayStartHour);
  }
}
