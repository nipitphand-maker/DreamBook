import 'package:sqflite_sqlcipher/sqflite.dart';

/// v3 → v4.
///
/// Idempotent recovery migration for devices where m003 partially applied
/// (i.e. the ALTER TABLE DDL auto-committed before the surrounding transaction
/// rolled back on a crash, leaving the schema in an inconsistent state).
///
/// All steps use IF NOT EXISTS / column-existence checks so this migration is
/// safe to run even when m003 applied cleanly.
Future<void> m004V4(Database db) async {
  // Ensure the two new tables exist regardless of whether m003 fully ran.
  await db.execute('''
    CREATE TABLE IF NOT EXISTS family_metadata (
      id TEXT PRIMARY KEY,
      current_key_version INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS key_rotation_state (
      family_id TEXT PRIMARY KEY,
      target_key_version INTEGER NOT NULL,
      started_at TEXT NOT NULL,
      last_processed_row TEXT
    )
  ''');

  // Tables that should have received family_id + key_version in m003.
  const syncable = [
    'baby',
    'caregiver',
    'pump_session',
    'stash_bottle',
    'feed',
    'diaper',
    'sleep',
    'vaccination',
  ];

  for (final t in syncable) {
    await _addColumnIfMissing(
        db, t, 'family_id', "TEXT NOT NULL DEFAULT ''");
    await _addColumnIfMissing(
        db, t, 'key_version', 'INTEGER NOT NULL DEFAULT 1');
  }

  // caregiver also received device_pub_key in m003.
  await _addColumnIfMissing(db, 'caregiver', 'device_pub_key', 'BLOB');
}

/// Adds [column] to [table] only when it does not already exist.
/// Uses PRAGMA table_info to avoid a try/catch that swallows real errors.
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
