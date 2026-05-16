import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/providers/day_start_hour_provider.dart';
import 'package:dreambook/core/sync/sync_lifecycle_controller.dart';
import 'package:dreambook/core/utils/day_boundary.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Local persistence for Sleep sessions.
///
/// All writes go through a transaction that ALSO updates the `sync_state`
/// ledger so the Plan C sync layer can find dirty rows. IDs and timestamps
/// are generated Dart-side (UTC ISO-8601 + v4 UUID) — never relying on
/// SQLite's clock.
class SleepRepository {
  SleepRepository(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  Future<Database> get _db => _ref.read(appDatabaseProvider.future);

  /// All non-deleted sleep sessions for [babyId] that fall within the logical
  /// day containing [now] (defaults to `DateTime.now()`), as defined by
  /// [dayStartHour]. Sessions started before [dayStartHour] are attributed to
  /// the previous calendar day. Ordered by `started_at DESC` — freshest first.
  ///
  /// [dayStartHour] defaults to 0 (midnight) for backward compatibility.
  Future<List<Sleep>> todayFor(
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
      'sleep',
      where:
          'baby_id = ? AND deleted_at IS NULL AND started_at >= ? AND started_at < ?',
      whereArgs: [babyId, startStr, endStr],
      orderBy: 'started_at DESC',
    );
    return rows.map(Sleep.fromRow).toList(growable: false);
  }

  /// Returns the most recent ongoing sleep session (ended_at IS NULL) for
  /// [babyId], or null if the baby is not currently sleeping.
  Future<Sleep?> activeFor(String babyId) async {
    final db = await _db;
    final rows = await db.query(
      'sleep',
      where: 'baby_id = ? AND ended_at IS NULL AND deleted_at IS NULL',
      whereArgs: [babyId],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Sleep.fromRow(rows.first);
  }

  /// Insert a new ongoing sleep session (endedAt = null, durationMin = null).
  /// Writes sync_state dirty row.
  /// Invalidates [sleepTodayProvider] and [sleepActiveProvider] for [babyId].
  Future<Sleep> start({
    required String babyId,
    required DateTime startedAt,
    SleepLocation? location,
    String? note,
  }) async {
    final db = await _db;
    final now = DateTime.now().toUtc();
    final sleep = Sleep(
      id: _uuid.v4(),
      babyId: babyId,
      startedAt: startedAt.toUtc(),
      endedAt: null,
      durationMin: null,
      location: location,
      note: note,
      createdAt: now,
      updatedAt: now,
    );

    await db.transaction((txn) async {
      await txn.insert('sleep', sleep.toRow());
      await txn.insert(
        'sync_state',
        {
          'record_id': sleep.id,
          'table_name': 'sleep',
          'version': sleep.version,
          'updated_at': now.toIso8601String(),
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _ref.invalidate(sleepTodayProvider(babyId));
    _ref.invalidate(sleepActiveProvider(babyId));
    _ref.read(syncLifecycleControllerProvider).schedulePush();
    return sleep;
  }

  /// End an ongoing sleep session. Calculates durationMin from the difference
  /// between endedAt and startedAt. Bumps version, writes sync_state dirty.
  /// Invalidates [sleepTodayProvider] and [sleepActiveProvider] for [babyId].
  Future<Sleep> end(
    String id, {
    required String babyId,
    required DateTime endedAt,
  }) async {
    final db = await _db;
    final now = DateTime.now().toUtc();
    final nowStr = now.toIso8601String();
    final endedAtStr = endedAt.toUtc().toIso8601String();

    late Sleep updated;

    await db.transaction((txn) async {
      // Fetch startedAt to compute duration — guard deleted rows so we never
      // attempt to end a soft-deleted session.
      final rows = await txn.query(
        'sleep',
        columns: ['started_at', 'version'],
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Sleep record $id not found or already deleted');
      }

      final startedAt = DateTime.parse(rows.first['started_at']! as String);
      final durationMin = endedAt.toUtc().difference(startedAt).inMinutes;
      final newVersion = (rows.first['version']! as int) + 1;

      final affected = await txn.rawUpdate(
        '''
        UPDATE sleep
        SET ended_at     = ?,
            duration_min = ?,
            updated_at   = ?,
            version      = ?
        WHERE id = ? AND ended_at IS NULL
        ''',
        [endedAtStr, durationMin, nowStr, newVersion, id],
      );
      if (affected == 0) {
        throw StateError('Sleep session already ended by concurrent write');
      }

      await txn.insert(
        'sync_state',
        {
          'record_id': id,
          'table_name': 'sleep',
          'version': newVersion,
          'updated_at': nowStr,
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Fetch the updated row to return a fully hydrated Sleep object
      final updatedRows = await txn.query(
        'sleep',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      updated = Sleep.fromRow(updatedRows.first);
    });

    _ref.invalidate(sleepTodayProvider(babyId));
    _ref.invalidate(sleepActiveProvider(babyId));
    _ref.read(syncLifecycleControllerProvider).schedulePush();
    return updated;
  }

  /// Insert a completed past sleep session with known start + end times.
  /// Calculates durationMin automatically. Writes sync_state dirty.
  Future<Sleep> insertPast({
    required String babyId,
    required DateTime startedAt,
    required DateTime endedAt,
    SleepLocation? location,
    String? note,
  }) async {
    final db = await _db;
    final now = DateTime.now().toUtc();
    final durationMin = endedAt.toUtc().difference(startedAt.toUtc()).inMinutes;
    final sleep = Sleep(
      id: _uuid.v4(),
      babyId: babyId,
      startedAt: startedAt.toUtc(),
      endedAt: endedAt.toUtc(),
      durationMin: durationMin,
      location: location,
      note: note,
      createdAt: now,
      updatedAt: now,
    );

    await db.transaction((txn) async {
      await txn.insert('sleep', sleep.toRow());
      await txn.insert(
        'sync_state',
        {
          'record_id': sleep.id,
          'table_name': 'sleep',
          'version': sleep.version,
          'updated_at': now.toIso8601String(),
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _ref.invalidate(sleepTodayProvider(babyId));
    _ref.invalidate(sleepActiveProvider(babyId));
    _ref.read(syncLifecycleControllerProvider).schedulePush();
    return sleep;
  }

  /// Soft-delete: stamps `deleted_at`, bumps version, marks `sync_state` dirty.
  /// Invalidates [sleepTodayProvider] and [sleepActiveProvider] for [babyId].
  Future<void> softDelete(String id, {required String babyId}) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      final affected = await txn.rawUpdate(
        '''
        UPDATE sleep
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
              'SELECT version FROM sleep WHERE id = ?',
              [id],
            ),
          ) ??
          1;

      await txn.insert(
        'sync_state',
        {
          'record_id': id,
          'table_name': 'sleep',
          'version': newVersion,
          'updated_at': now,
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _ref.invalidate(sleepTodayProvider(babyId));
    _ref.invalidate(sleepActiveProvider(babyId));
    _ref.read(syncLifecycleControllerProvider).schedulePush();
  }

  /// Update mutable fields on an existing Sleep session. Bumps version, writes
  /// sync_state dirty. Recalculates [durationMin] if both [startedAt] and
  /// [endedAt] are present. Throws [StateError] if [sleep.id] does not exist.
  ///
  /// Invalidates [sleepTodayProvider] and [sleepActiveProvider] for
  /// [sleep.babyId] on success.
  Future<void> update(Sleep sleep) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    final endedAtStr = sleep.endedAt?.toUtc().toIso8601String();
    final durationMin = sleep.endedAt
        ?.toUtc()
        .difference(sleep.startedAt.toUtc())
        .inMinutes;

    await db.transaction((txn) async {
      final affected = await txn.rawUpdate(
        '''
        UPDATE sleep
        SET started_at   = ?,
            ended_at     = ?,
            duration_min = ?,
            note         = ?,
            updated_at   = ?,
            version      = version + 1
        WHERE id = ? AND deleted_at IS NULL
        ''',
        [
          sleep.startedAt.toUtc().toIso8601String(),
          endedAtStr,
          durationMin,
          sleep.note,
          now,
          sleep.id,
        ],
      );
      if (affected == 0) {
        throw StateError('Sleep ${sleep.id} not found or already deleted');
      }

      final newVersion = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT version FROM sleep WHERE id = ?',
              [sleep.id],
            ),
          ) ??
          1;

      await txn.insert(
        'sync_state',
        {
          'record_id': sleep.id,
          'table_name': 'sleep',
          'version': newVersion,
          'updated_at': now,
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _ref.invalidate(sleepTodayProvider(sleep.babyId));
    _ref.invalidate(sleepActiveProvider(sleep.babyId));
    _ref.read(syncLifecycleControllerProvider).schedulePush();
  }
}

final sleepRepositoryProvider =
    Provider<SleepRepository>(SleepRepository.new);

/// Today's sleep sessions for [babyId], ordered `started_at DESC`,
/// excluding soft-deleted. Invalidated by every [SleepRepository] write.
final sleepTodayProvider =
    AsyncNotifierProvider.family<SleepTodayNotifier, List<Sleep>, String>(
  SleepTodayNotifier.new,
);

class SleepTodayNotifier extends AsyncNotifier<List<Sleep>> {
  SleepTodayNotifier(this.babyId);

  final String babyId;

  @override
  Future<List<Sleep>> build() {
    final dayStartHour = ref.watch(dayStartHourProvider);
    return ref
        .read(sleepRepositoryProvider)
        .todayFor(babyId, dayStartHour: dayStartHour);
  }
}

/// The current ongoing sleep session for [babyId], or null if awake.
/// Invalidated by every [SleepRepository] write.
final sleepActiveProvider =
    AsyncNotifierProvider.family<SleepActiveNotifier, Sleep?, String>(
  SleepActiveNotifier.new,
);

class SleepActiveNotifier extends AsyncNotifier<Sleep?> {
  SleepActiveNotifier(this.babyId);

  final String babyId;

  @override
  Future<Sleep?> build() =>
      ref.read(sleepRepositoryProvider).activeFor(babyId);
}

/// Total sleep minutes today (sum of durationMin for completed sessions).
final sleepMinutesTodayProvider = Provider.family<AsyncValue<int>, String>(
  (ref, babyId) => ref.watch(sleepTodayProvider(babyId)).whenData(
        (sleeps) => sleeps.fold<int>(0, (sum, s) => sum + (s.durationMin ?? 0)),
      ),
);
