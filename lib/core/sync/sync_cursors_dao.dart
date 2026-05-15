import 'package:sqflite_sqlcipher/sqflite.dart';

/// Data-access object for the `sync_cursors` table.
///
/// Each row tracks the latest server-side `updated_at` timestamp that this
/// device has successfully applied for a given family. On cold start, the
/// [SyncWorker] reads this cursor so it only fetches rows newer than the last
/// successful pull (incremental sync).
///
/// Passing `null` to [writeLastPullAt] deletes the cursor row, which causes
/// the next pull to fetch all rows from the beginning of time (full re-sync).
class SyncCursorsDao {
  const SyncCursorsDao({required this.db});

  final Database db;

  /// Returns the persisted `last_pull_at` for [familyId], or `null` when no
  /// cursor row exists (fresh device or cursor has been reset).
  Future<DateTime?> readLastPullAt(String familyId) async {
    final rows = await db.query(
      'sync_cursors',
      columns: ['last_pull_at'],
      where: 'family_id = ?',
      whereArgs: [familyId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = rows.first['last_pull_at'];
    if (value == null) return null;
    return DateTime.tryParse(value as String);
  }

  /// Persists [cursor] as the latest applied server timestamp for [familyId].
  ///
  /// Pass `null` to delete the cursor row entirely, which resets sync to a
  /// full re-fetch on the next pull (used by [CountAttestation] on mismatch).
  Future<void> writeLastPullAt(String familyId, DateTime? cursor) async {
    if (cursor == null) {
      await db.delete(
        'sync_cursors',
        where: 'family_id = ?',
        whereArgs: [familyId],
      );
      return;
    }
    await db.insert(
      'sync_cursors',
      {
        'family_id': familyId,
        'last_pull_at': cursor.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
