import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/core/sync/sync_constants.dart';
import 'package:dreambook/core/sync/sync_lifecycle_controller.dart';
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

  /// Display name caps (defense-in-depth alongside `TextField.maxLength` on
  /// the input screens). Caught here so direct repository callers (tests,
  /// future programmatic flows) can't bypass UI limits.
  static const int maxNameLength = 80;
  static const int maxNicknameLength = 40;

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
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    if (trimmedName.length > maxNameLength) {
      throw ArgumentError.value(name, 'name',
          'must be at most $maxNameLength characters');
    }
    final trimmedNickname = nickname?.trim();
    if (trimmedNickname != null && trimmedNickname.length > maxNicknameLength) {
      throw ArgumentError.value(nickname, 'nickname',
          'must be at most $maxNicknameLength characters');
    }

    final db = await _db;
    final now = DateTime.now().toUtc();
    final baby = Baby(
      id: _uuid.v4(),
      name: trimmedName,
      nickname: trimmedNickname?.isEmpty == true ? null : trimmedNickname,
      dob: dob,
      sex: sex,
      photoPath: photoPath,
      preferredUnit: preferredUnit,
      createdAt: now,
      updatedAt: now,
    );

    // Stamp the active family_id from prefs so this row is visible to
    // `list()` (which filters by `family_id = prefs[kFamilyIdPrefsKey]`). Skip the
    // stamp when prefs is empty — keeps schema-v2 tests (no family_id column)
    // green and falls back to the DDL default (`''`) for offline installs
    // that never bootstrapped a remote family.
    final familyId =
        _ref.read(sharedPreferencesProvider).getString(kFamilyIdPrefsKey) ?? '';
    final row = {...baby.toRow()};
    if (familyId.isNotEmpty) {
      row['family_id'] = familyId;
    }

    await db.transaction((txn) async {
      await txn.insert('baby', row);
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

    _ref.read(syncLifecycleControllerProvider).schedulePush();
    return baby;
  }

  /// Alias for [insert] — preferred name for Plan D multi-baby UI.
  ///
  /// Plan B introduced [insert]; Plan D's Multi-baby team uses [create]. Both
  /// names persist to keep existing tests + callers green.
  Future<Baby> create({
    required String name,
    String? nickname,
    required DateTime dob,
    BabySex? sex,
    String? photoPath,
    PreferredUnit preferredUnit = PreferredUnit.oz,
  }) =>
      insert(
        name: name,
        nickname: nickname,
        dob: dob,
        sex: sex,
        photoPath: photoPath,
        preferredUnit: preferredUnit,
      );

  /// Returns the single non-deleted baby (Plan B is single-baby UI).
  /// Returns null if no babies exist yet.
  Future<Baby?> getActive() async {
    final db = await _db;
    final familyId =
        _ref.read(sharedPreferencesProvider).getString(kFamilyIdPrefsKey) ?? '';
    final (where, whereArgs) = familyId.isEmpty
        ? ('deleted_at IS NULL', <Object?>[])
        : ('deleted_at IS NULL AND family_id = ?', [familyId]);
    final rows = await db.query(
      'baby',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'created_at ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Baby.fromRow(rows.first);
  }

  /// All non-deleted babies, oldest first (created_at ASC).
  Future<List<Baby>> list() async {
    final db = await _db;
    final familyId =
        _ref.read(sharedPreferencesProvider).getString(kFamilyIdPrefsKey) ?? '';
    final (where, whereArgs) = familyId.isEmpty
        ? ('deleted_at IS NULL', <Object?>[])
        : ('deleted_at IS NULL AND family_id = ?', [familyId]);
    final rows = await db.query(
      'baby',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'created_at ASC',
    );
    return rows.map(Baby.fromRow).toList(growable: false);
  }

  /// Alias for [list] — preferred name for Plan D multi-baby UI.
  Future<List<Baby>> getAll() => list();

  /// Update mutable profile fields (name, nickname, dob, sex, preferredUnit).
  Future<void> update({
    required String id,
    required String name,
    String? nickname,
    required DateTime dob,
    BabySex? sex,
    PreferredUnit preferredUnit = PreferredUnit.oz,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    if (trimmedName.length > maxNameLength) {
      throw ArgumentError.value(name, 'name',
          'must be at most $maxNameLength characters');
    }
    final trimmedNickname = nickname?.trim();
    if (trimmedNickname != null && trimmedNickname.length > maxNicknameLength) {
      throw ArgumentError.value(nickname, 'nickname',
          'must be at most $maxNicknameLength characters');
    }

    final db = await _db;
    final now = DateTime.now().toUtc();
    final nowIso = now.toIso8601String();
    final sexStr = switch (sex) {
      BabySex.male => 'male',
      BabySex.female => 'female',
      _ => 'unspecified',
    };
    final unitStr = preferredUnit == PreferredUnit.oz ? 'oz' : 'ml';

    await db.transaction((txn) async {
      final affected = await txn.rawUpdate(
        '''
        UPDATE baby
        SET name           = ?,
            nickname       = ?,
            dob            = ?,
            sex            = ?,
            preferred_unit = ?,
            updated_at     = ?,
            version        = version + 1
        WHERE id = ? AND deleted_at IS NULL
        ''',
        [
          trimmedName,
          trimmedNickname?.isEmpty == true ? null : trimmedNickname,
          dob.toUtc().toIso8601String(),
          sexStr,
          unitStr,
          nowIso,
          id,
        ],
      );
      if (affected == 0) {
        throw StateError('Baby $id not found or already deleted');
      }
      final rows = await txn.query('baby', columns: ['version'], where: 'id = ?', whereArgs: [id], limit: 1);
      final newVersion = rows.isEmpty ? 1 : rows.first['version'] as int;
      await txn.insert(
        'sync_state',
        {'record_id': id, 'table_name': 'baby', 'version': newVersion, 'updated_at': nowIso, 'dirty': 1},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    _ref.read(syncLifecycleControllerProvider).schedulePush();
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
    _ref.read(syncLifecycleControllerProvider).schedulePush();
  }
}

final babyRepositoryProvider =
    Provider<BabyRepository>(BabyRepository.new);
