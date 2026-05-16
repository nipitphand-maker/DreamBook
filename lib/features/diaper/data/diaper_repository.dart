import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/providers/day_start_hour_provider.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/core/sync/sync_lifecycle_controller.dart';
import 'package:dreambook/core/utils/day_boundary.dart';
import 'package:dreambook/features/diaper/data/diaper_stock_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Local persistence for Diaper entries.
///
/// All writes go through a transaction that ALSO updates the `sync_state`
/// ledger so the Plan C sync layer can find dirty rows. IDs and timestamps
/// are generated Dart-side (UTC ISO-8601 + v4 UUID) — never relying on
/// SQLite's clock.
class DiaperRepository {
  DiaperRepository(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  Future<Database> get _db => _ref.read(appDatabaseProvider.future);

  /// All non-deleted diapers for [babyId] that fall within the logical day
  /// containing [now] (defaults to `DateTime.now()`), as defined by
  /// [dayStartHour]. Events before [dayStartHour] are attributed to the
  /// previous calendar day. Ordered by `occurred_at DESC` — freshest first.
  ///
  /// [dayStartHour] defaults to 0 (midnight) for backward compatibility.
  Future<List<Diaper>> todayFor(
    String babyId, {
    DateTime? now,
    int dayStartHour = 0,
  }) async {
    final db = await _db;
    final n = now ?? DateTime.now();
    final (start, end) = logicalDayBounds(n, dayStartHour);
    final startStr = start.toUtc().toIso8601String();
    final endStr = end.toUtc().toIso8601String();
    final rows = await db.query(
      'diaper',
      where:
          'baby_id = ? AND deleted_at IS NULL AND occurred_at >= ? AND occurred_at < ?',
      whereArgs: [babyId, startStr, endStr],
      orderBy: 'occurred_at DESC',
    );
    return rows.map(Diaper.fromRow).toList(growable: false);
  }

  /// Insert a new Diaper row atomically with a `sync_state` row (dirty=1).
  ///
  /// [occurredAt] defaults to `DateTime.now()` if null.
  /// Invalidates [diaperTodayProvider] for [babyId] on success.
  Future<Diaper> insert({
    required String babyId,
    required DiaperType type,
    DateTime? occurredAt,
    String? color,
    String? consistency,
    String? note,
    String? loggedBy,
  }) async {
    final db = await _db;
    final now = DateTime.now().toUtc();
    final diaper = Diaper(
      id: _uuid.v4(),
      babyId: babyId,
      type: type,
      color: color,
      consistency: consistency,
      occurredAt: (occurredAt ?? now).toUtc(),
      note: note,
      loggedBy: loggedBy,
      createdAt: now,
      updatedAt: now,
    );

    await db.transaction((txn) async {
      await txn.insert('diaper', diaper.toRow());
      await txn.insert(
        'sync_state',
        {
          'record_id': diaper.id,
          'table_name': 'diaper',
          'version': diaper.version,
          'updated_at': now.toIso8601String(),
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    // Decrement diaper stock counter (no-op if user hasn't opted into
    // tracking). Invalidate so the Home banner re-renders.
    final prefs = _ref.read(sharedPreferencesProvider);
    await DiaperStockService.decrement(prefs, babyId);
    _ref.invalidate(diaperStockProvider(babyId));

    _ref.invalidate(diaperTodayProvider(babyId));
    _ref.read(syncLifecycleControllerProvider).schedulePush();
    return diaper;
  }

  /// Soft-delete: stamps `deleted_at`, bumps version, marks `sync_state` dirty.
  ///
  /// No-op if [id] does not exist (zero rows updated).
  /// Invalidates [diaperTodayProvider] for [babyId].
  Future<void> softDelete(String id, {required String babyId}) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      final affected = await txn.rawUpdate(
        '''
        UPDATE diaper
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
              'SELECT version FROM diaper WHERE id = ?',
              [id],
            ),
          ) ??
          1;

      await txn.insert(
        'sync_state',
        {
          'record_id': id,
          'table_name': 'diaper',
          'version': newVersion,
          'updated_at': now,
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _ref.invalidate(diaperTodayProvider(babyId));
    _ref.read(syncLifecycleControllerProvider).schedulePush();
  }

  /// Update mutable fields on an existing Diaper entry. Bumps version, writes
  /// sync_state dirty. Throws [StateError] if [diaper.id] does not exist.
  ///
  /// Invalidates [diaperTodayProvider] for [diaper.babyId] on success.
  Future<void> update(Diaper diaper) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      final affected = await txn.rawUpdate(
        '''
        UPDATE diaper
        SET type        = ?,
            occurred_at = ?,
            note        = ?,
            updated_at  = ?,
            version     = version + 1
        WHERE id = ? AND deleted_at IS NULL
        ''',
        [
          diaper.type.name,
          diaper.occurredAt.toUtc().toIso8601String(),
          diaper.note,
          now,
          diaper.id,
        ],
      );
      if (affected == 0) {
        throw StateError('Diaper ${diaper.id} not found or already deleted');
      }

      final newVersion = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT version FROM diaper WHERE id = ?',
              [diaper.id],
            ),
          ) ??
          1;

      await txn.insert(
        'sync_state',
        {
          'record_id': diaper.id,
          'table_name': 'diaper',
          'version': newVersion,
          'updated_at': now,
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _ref.invalidate(diaperTodayProvider(diaper.babyId));
    _ref.read(syncLifecycleControllerProvider).schedulePush();
  }
}

final diaperRepositoryProvider =
    Provider<DiaperRepository>(DiaperRepository.new);

/// Today's diaper entries for the given `babyId`, ordered `occurred_at DESC`,
/// excluding soft-deleted. Invalidated by every [DiaperRepository] write.
final diaperTodayProvider =
    AsyncNotifierProvider.family<DiaperTodayNotifier, List<Diaper>, String>(
  DiaperTodayNotifier.new,
);

class DiaperTodayNotifier extends AsyncNotifier<List<Diaper>> {
  DiaperTodayNotifier(this.babyId);

  final String babyId;

  @override
  Future<List<Diaper>> build() {
    final dayStartHour = ref.watch(dayStartHourProvider);
    return ref
        .read(diaperRepositoryProvider)
        .todayFor(babyId, dayStartHour: dayStartHour);
  }
}

/// Count of diapers logged today for [babyId].
/// Derived from [diaperTodayProvider] — one read path, free consistency.
final diaperCountTodayProvider = Provider.family<AsyncValue<int>, String>(
  (ref, babyId) => ref.watch(diaperTodayProvider(babyId)).whenData(
        (d) => d.length,
      ),
);

/// The most recent diaper entry today for [babyId], or null if none.
/// `diaperTodayProvider` is already ordered `occurred_at DESC`, so `d.first`
/// yields the latest entry.
final diaperLastTodayProvider = Provider.family<AsyncValue<Diaper?>, String>(
  (ref, babyId) => ref.watch(diaperTodayProvider(babyId)).whenData(
        (d) => d.isEmpty ? null : d.first,
      ),
);
