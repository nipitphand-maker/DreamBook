import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

/// v2 → v3.
///
/// Adds `family_id` + `key_version` columns to every syncable table
/// (per spec §3.1) and creates `family_metadata` + `key_rotation_state`.
/// Existing rows are backfilled with a single newly-generated `family_id`
/// representing the upgrading user's family. `device_pub_key` column is
/// added to `caregiver` for the handshake fan-out flow.
///
/// NOTE: SQLite auto-commits every DDL statement regardless of any wrapping
/// transaction, so DDL (CREATE TABLE, ALTER TABLE) is run sequentially
/// without a transaction wrapper. The IF NOT EXISTS guard on CREATE TABLE
/// makes this step idempotent against the partial-apply scenario handled by
/// m004 on existing devices.
Future<void> m003V3(Database db) async {
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

  final uuid = const Uuid().v4();
  final now = DateTime.now().toUtc().toIso8601String();

  // --- DDL: run outside any transaction (SQLite auto-commits DDL anyway) ---

  for (final t in syncable) {
    await _addColumnIfMissing(
        db, t, 'family_id', "TEXT NOT NULL DEFAULT ''");
    await _addColumnIfMissing(
        db, t, 'key_version', 'INTEGER NOT NULL DEFAULT 1');
  }

  await _addColumnIfMissing(db, 'caregiver', 'device_pub_key', 'BLOB');

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

  // --- DML: backfill existing rows inside a transaction ---

  await db.transaction((txn) async {
    final anyBaby = await txn.rawQuery('SELECT COUNT(*) AS c FROM baby');
    final count = (anyBaby.first['c'] as int?) ?? 0;
    if (count > 0) {
      await txn.insert('family_metadata', {
        'id': uuid,
        'current_key_version': 1,
        'created_at': now,
      });
      for (final t in syncable) {
        await txn.update(t, {'family_id': uuid});
      }
    }
  });
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
