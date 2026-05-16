import 'package:sqflite_sqlcipher/sqflite.dart';

/// Migration v1 → v2 (Plan B foundation).
/// Adds: stash_bottle{thawed_at, parent_bottle_id, source}
///       pump_session{paused_duration_min}
///
/// All ADD COLUMN steps are guarded by [_addColumnIfMissing] so this
/// migration is safe to re-run after a mid-migration crash.
Future<void> m002V2(Database db) async {
  // SQLite ALTER TABLE only supports ADD COLUMN one at a time.
  // None of these can be NOT NULL without a DEFAULT — all add cleanly.
  await _addColumnIfMissing(db, 'stash_bottle', 'thawed_at', 'TEXT');
  await _addColumnIfMissing(
      db,
      'stash_bottle',
      'parent_bottle_id',
      'TEXT REFERENCES stash_bottle(id) ON DELETE SET NULL');
  // SQLite cannot add a CHECK constraint via ALTER TABLE — the CHECK lives
  // in the column-definition only at CREATE TABLE time. We enforce the
  // enum in the repository layer (Dart) instead (Plan B B4.1).
  await _addColumnIfMissing(
      db, 'stash_bottle', 'source', "TEXT NOT NULL DEFAULT 'pump'");
  await _addColumnIfMissing(
      db, 'pump_session', 'paused_duration_min', 'INTEGER NOT NULL DEFAULT 0');

  // Update schema_version meta row.
  await db.update(
    'meta',
    {
      'value': '2',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    },
    where: 'key = ?',
    whereArgs: ['schema_version'],
  );
}

Future<void> _addColumnIfMissing(
  Database db,
  String table,
  String column,
  String definition,
) async {
  final info = await db.rawQuery('PRAGMA table_info($table)');
  final exists = info.any((row) => row['name'] == column);
  if (!exists) {
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }
}
