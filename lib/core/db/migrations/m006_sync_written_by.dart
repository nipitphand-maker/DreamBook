import 'package:sqflite_sqlcipher/sqflite.dart';

/// v5 → v6: Track which device last touched each sync_state row so
/// ConflictResolver can break same-version ties deterministically.
///
/// ADD COLUMN is guarded by [_addColumnIfMissing] so this migration is
/// safe to re-run after a mid-migration crash.
Future<void> m006SyncWrittenBy(Database db) async {
  await _addColumnIfMissing(db, 'sync_state', 'written_by_device', 'TEXT');
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
