import 'package:sqflite_sqlcipher/sqflite.dart';

/// v5 → v6: Track which device last touched each sync_state row so
/// ConflictResolver can break same-version ties deterministically.
Future<void> m006SyncWrittenBy(Database db) async {
  await db.execute(
    'ALTER TABLE sync_state ADD COLUMN written_by_device TEXT',
  );
}
