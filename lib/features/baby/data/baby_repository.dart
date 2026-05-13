import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Local persistence for the Baby entity.
///
/// All writes happen inside a transaction that ALSO updates the `sync_state`
/// ledger so the Plan C sync layer can find dirty rows. Timestamps and IDs are
/// generated Dart-side (UTC ISO-8601 + v4 UUID) — never relying on SQLite.
class BabyRepository {
  BabyRepository(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  Future<Database> get _db => _ref.read(appDatabaseProvider.future);

  /// Insert a new Baby row with a Dart-generated v4 UUID.
  /// Returns the domain model that was just persisted.
  Future<Baby> insert({
    required String name,
    String? nickname,
    required DateTime dob,
    BabySex? sex,
    String? photoPath,
    PreferredUnit preferredUnit = PreferredUnit.oz,
  }) async {
    final db = await _db;
    final now = DateTime.now().toUtc();
    final baby = Baby(
      id: _uuid.v4(),
      name: name,
      nickname: nickname,
      dob: dob,
      sex: sex,
      photoPath: photoPath,
      preferredUnit: preferredUnit,
      createdAt: now,
      updatedAt: now,
    );

    await db.transaction((txn) async {
      await txn.insert('baby', baby.toRow());
      await txn.insert(
        'sync_state',
        {
          'record_id': baby.id,
          'table_name': 'baby',
          'version': baby.version,
          'updated_at': now.toIso8601String(),
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    return baby;
  }

  /// Returns the single non-deleted baby (Plan B is single-baby UI).
  /// Returns null if no babies exist yet.
  Future<Baby?> getActive() async {
    final db = await _db;
    final rows = await db.query(
      'baby',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Baby.fromRow(rows.first);
  }

  /// All non-deleted babies, oldest first (created_at ASC).
  Future<List<Baby>> list() async {
    final db = await _db;
    final rows = await db.query(
      'baby',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at ASC',
    );
    return rows.map(Baby.fromRow).toList(growable: false);
  }

  /// Soft-delete: sets deleted_at, bumps version, marks sync_state dirty.
  Future<void> softDelete(String id) async {
    final db = await _db;
    final now = DateTime.now().toUtc();
    final nowIso = now.toIso8601String();

    await db.transaction((txn) async {
      // Bump version + stamp deleted_at/updated_at atomically.
      await txn.rawUpdate(
        '''
        UPDATE baby
        SET deleted_at = ?,
            updated_at = ?,
            version    = version + 1
        WHERE id = ?
        ''',
        [nowIso, nowIso, id],
      );

      // Read back the new version to mirror into sync_state.
      final rows = await txn.query(
        'baby',
        columns: ['version'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final newVersion = rows.isEmpty ? 1 : rows.first['version'] as int;

      await txn.insert(
        'sync_state',
        {
          'record_id': id,
          'table_name': 'baby',
          'version': newVersion,
          'updated_at': nowIso,
          'dirty': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }
}

final babyRepositoryProvider =
    Provider<BabyRepository>(BabyRepository.new);
