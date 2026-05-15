import 'package:sqflite_sqlcipher/sqflite.dart';

import 'sync_cursors_dao.dart';
import 'sync_server.dart';

const List<String> _syncableTables = [
  'baby',
  'caregiver',
  'pump_session',
  'stash_bottle',
  'feed',
  'diaper',
  'sleep',
  'vaccination',
  'daily_note',
];

/// Compares server-side row counts against local non-tombstoned counts for all
/// syncable tables. If any table's counts diverge, the sync cursor is reset to
/// `null` so that the next [SyncWorker.pullOnce] performs a full re-fetch.
///
/// This is a lightweight integrity check run at the end of each pull cycle
/// (P2.20 SY-9). It catches scenarios where rows were silently lost (e.g. a
/// failed upsert, a migration bug, or a corrupt write) before the app surfaces
/// stale data to the user.
class CountAttestation {
  CountAttestation({
    required this.db,
    required this.server,
    required this.cursors,
    required this.familyId,
    this.onMismatch,
  });

  final Database db;
  final SyncServer server;
  final SyncCursorsDao cursors;
  final String familyId;

  /// Called when at least one table's local count differs from the server
  /// count. The map contains only diverging tables; values are `(local, remote)`.
  final void Function(Map<String, (int, int)> diff)? onMismatch;

  /// Returns `true` when all syncable table counts match between local DB and
  /// the server. On mismatch: calls [onMismatch] with the diff, resets the
  /// sync cursor to `null` (triggers full re-pull next cycle), and returns
  /// `false`.
  Future<bool> verify() async {
    final serverCounts = await server.countRows(familyId: familyId);

    final localCounts = <String, int>{};
    for (final table in _syncableTables) {
      final result = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM $table WHERE deleted_at IS NULL',
      );
      final count = Sqflite.firstIntValue(result) ?? 0;
      if (count > 0) localCounts[table] = count;
    }

    // Find tables where counts differ.
    final allTables = {
      ...serverCounts.keys,
      ...localCounts.keys,
    };
    final diff = <String, (int, int)>{};
    for (final table in allTables) {
      final local = localCounts[table] ?? 0;
      final remote = serverCounts[table] ?? 0;
      if (local != remote) diff[table] = (local, remote);
    }

    if (diff.isEmpty) return true;

    onMismatch?.call(diff);
    await cursors.writeLastPullAt(familyId, null);
    return false;
  }
}
