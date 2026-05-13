import 'package:sqflite_sqlcipher/sqflite.dart';

/// Migration v1 → v2 (Plan B foundation).
/// Adds: stash_bottle{thawed_at, parent_bottle_id, source}
///       pump_session{paused_duration_min}
Future<void> m002V2(Database db) async {
  // SQLite ALTER TABLE only supports ADD COLUMN one at a time.
  // None of these can be NOT NULL without a DEFAULT — all add cleanly.
  await db.execute('ALTER TABLE stash_bottle ADD COLUMN thawed_at TEXT');
  await db.execute(
      'ALTER TABLE stash_bottle ADD COLUMN parent_bottle_id TEXT REFERENCES stash_bottle(id) ON DELETE SET NULL');
  // SQLite cannot add a CHECK constraint via ALTER TABLE — the CHECK lives
  // in the column-definition only at CREATE TABLE time. We enforce the
  // enum in the repository layer (Dart) instead (Plan B B4.1).
  await db.execute(
      "ALTER TABLE stash_bottle ADD COLUMN source TEXT NOT NULL DEFAULT 'pump'");
  await db.execute(
      'ALTER TABLE pump_session ADD COLUMN paused_duration_min INTEGER NOT NULL DEFAULT 0');

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
