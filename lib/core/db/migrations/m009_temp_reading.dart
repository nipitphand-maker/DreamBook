import 'package:sqflite_sqlcipher/sqflite.dart';

Future<void> m009TempReading(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS temp_reading (
      id TEXT PRIMARY KEY,
      baby_id TEXT NOT NULL REFERENCES baby(id),
      taken_at TEXT NOT NULL,
      celsius REAL NOT NULL,
      version INTEGER NOT NULL DEFAULT 1,
      deleted_at TEXT,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_temp_baby_taken ON temp_reading(baby_id, taken_at DESC)',
  );
}
