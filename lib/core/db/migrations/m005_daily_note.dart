import 'package:sqflite_sqlcipher/sqflite.dart';

/// v4 → v5: Add daily_note table for per-day free-text notes.
Future<void> m005DailyNote(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS daily_note (
      id          TEXT PRIMARY KEY NOT NULL,
      baby_id     TEXT NOT NULL REFERENCES baby(id) ON DELETE CASCADE,
      date        TEXT NOT NULL,
      body        TEXT NOT NULL DEFAULT '',
      family_id   TEXT NOT NULL DEFAULT '',
      key_version INTEGER NOT NULL DEFAULT 1,
      created_at  TEXT NOT NULL,
      updated_at  TEXT NOT NULL,
      deleted_at  TEXT,
      version     INTEGER NOT NULL DEFAULT 1,
      UNIQUE (baby_id, date)
    )
  ''');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_daily_note_baby_date ON daily_note(baby_id, date)');
}
