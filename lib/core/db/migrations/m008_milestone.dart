import 'package:sqflite_sqlcipher/sqflite.dart';

Future<void> m008Milestone(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS milestone_achievement (
      id TEXT PRIMARY KEY,
      baby_id TEXT NOT NULL REFERENCES baby(id),
      milestone_id TEXT NOT NULL,
      achieved_on TEXT NOT NULL,
      note TEXT,
      version INTEGER NOT NULL DEFAULT 1,
      deleted_at TEXT,
      updated_at TEXT NOT NULL
    )
  ''');
}
