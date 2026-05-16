import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/sync/sync_lifecycle_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Local persistence for the [VaccinationRecord] entity.
///
/// Follows the same pattern as [FeedRepository]: every write goes through
/// a transaction that ALSO updates the `sync_state` ledger so the Plan C
/// sync layer can find dirty rows. IDs and timestamps are generated
/// Dart-side (UTC ISO-8601 + v4 UUID) — never relying on SQLite's clock.
class VaccinationRepository {
  VaccinationRepository(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  Future<Database> get _db => _ref.read(appDatabaseProvider.future);

  /// All non-deleted vaccination records for [babyId], ordered by
  /// `given_on DESC` — most recent shot first.
  Future<List<VaccinationRecord>> listFor(String babyId) async {
    final db = await _db;
    final rows = await db.query(
      'vaccination',
      where: 'baby_id = ? AND deleted_at IS NULL',
      whereArgs: [babyId],
      orderBy: 'given_on DESC',
    );
    return rows.map(VaccinationRecord.fromRow).toList(growable: false);
  }

  /// Insert a new vaccination record. Generates v4 UUID + timestamps
  /// Dart-side. Touches `sync_state` in the same transaction with
  /// `dirty=1`.
  ///
  /// Invalidates [vaccinationListProvider] for [babyId] on success so any
  /// open list rebuilds.
  Future<VaccinationRecord> insert({
    required String babyId,
    required String vaccineName,
    required DateTime givenOn,
    String? clinic,
    String? note,
    String? loggedBy,
  }) async {
    final db = await _db;
    final now = DateTime.now().toUtc();
    final record = VaccinationRecord(
      id: _uuid.v4(),
      babyId: babyId,
      vaccineName: vaccineName,
      givenOn: givenOn.toUtc(),
      clinic: clinic,
      note: note,
      loggedBy: loggedBy,
      createdAt: now,
      updatedAt: now,
    );

    await db.transaction((txn) async {
      await txn.insert('vaccination', record.toRow());
      await txn.insert(
        'sync_state',
        {
          'record_id': record.id,
          'table_name': 'vaccination',
          'version': record.version,
          'updated_at': now.toIso8601String(),
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _ref.invalidate(vaccinationListProvider(babyId));
    _ref.read(syncLifecycleControllerProvider).schedulePush();
    return record;
  }

  /// Soft-delete: stamps `deleted_at`, bumps version, marks `sync_state`
  /// dirty. No-op if [id] does not exist (zero rows updated).
  Future<void> softDelete(String id, {required String babyId}) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      final affected = await txn.rawUpdate(
        '''
        UPDATE vaccination
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
              'SELECT version FROM vaccination WHERE id = ?',
              [id],
            ),
          ) ??
          1;

      await txn.insert(
        'sync_state',
        {
          'record_id': id,
          'table_name': 'vaccination',
          'version': newVersion,
          'updated_at': now,
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _ref.invalidate(vaccinationListProvider(babyId));
    _ref.read(syncLifecycleControllerProvider).schedulePush();
  }
}

final vaccinationRepositoryProvider =
    Provider<VaccinationRepository>(VaccinationRepository.new);

/// Non-deleted vaccination records for the given `babyId`, ordered
/// `given_on DESC`. Invalidated by every [VaccinationRepository] write.
///
/// Riverpod 3 dropped the `FamilyAsyncNotifier` subclass — family
/// notifiers are now just `AsyncNotifier`s constructed per-arg, with
/// the arg held on the instance.
final vaccinationListProvider = AsyncNotifierProvider.family<
    VaccinationListNotifier, List<VaccinationRecord>, String>(
  VaccinationListNotifier.new,
);

class VaccinationListNotifier extends AsyncNotifier<List<VaccinationRecord>> {
  VaccinationListNotifier(this.babyId);

  final String babyId;

  @override
  Future<List<VaccinationRecord>> build() {
    final repo = ref.read(vaccinationRepositoryProvider);
    return repo.listFor(babyId);
  }
}
