import 'package:sqflite_sqlcipher/sqflite.dart';

/// v6 → v7: Add `sync_cursors` to persist per-family `last_pull_at` so that
/// cold-start does an incremental pull instead of re-fetching everything
/// from the beginning of time.
///
/// Schema:
///   family_id     TEXT PK NOT NULL — one row per family this device has joined
///   last_pull_at  TEXT     NOT NULL — ISO-8601 UTC of latest server-side
///                                     `updated_at` we've already applied
///   updated_at    TEXT     NOT NULL — when this cursor row itself was written
Future<void> m007SyncCursors(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sync_cursors (
      family_id    TEXT PRIMARY KEY NOT NULL,
      last_pull_at TEXT NOT NULL,
      updated_at   TEXT NOT NULL
    )
  ''');
}
