import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

/// v2 → v3.
///
/// Adds `family_id` + `key_version` columns to every syncable table
/// (per spec §3.1) and creates `family_metadata` + `key_rotation_state`.
/// Existing rows are backfilled with a single newly-generated `family_id`
/// representing the upgrading user's family. `device_pub_key` column is
/// added to `caregiver` for the handshake fan-out flow.
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

  await db.transaction((txn) async {
    for (final t in syncable) {
      await txn.execute("ALTER TABLE $t ADD COLUMN family_id TEXT NOT NULL DEFAULT ''");
      await txn.execute('ALTER TABLE $t ADD COLUMN key_version INTEGER NOT NULL DEFAULT 1');
    }

    await txn.execute('ALTER TABLE caregiver ADD COLUMN device_pub_key BLOB');

    await txn.execute('''
      CREATE TABLE family_metadata (
        id TEXT PRIMARY KEY,
        current_key_version INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');
    await txn.execute('''
      CREATE TABLE key_rotation_state (
        family_id TEXT PRIMARY KEY,
        target_key_version INTEGER NOT NULL,
        started_at TEXT NOT NULL,
        last_processed_row TEXT
      )
    ''');

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
