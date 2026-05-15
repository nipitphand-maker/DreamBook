import 'dart:typed_data';

import 'package:dreambook/core/sync/count_attestation.dart';
import 'package:dreambook/core/sync/sync_cursors_dao.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../_fakes/fake_supabase_server.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('CountAttestation', () {
    late Database db;
    late FakeSupabaseServer server;
    late SyncCursorsDao cursors;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) async {
              await db.execute('''CREATE TABLE feed (
                id TEXT PRIMARY KEY, baby_id TEXT, started_at TEXT, ended_at TEXT,
                feed_type TEXT, amount_oz REAL, side TEXT, note TEXT,
                deleted_at TEXT, version INTEGER, dirty INTEGER DEFAULT 0)''');
              await db.execute('''CREATE TABLE sync_cursors (
                family_id TEXT PRIMARY KEY,
                last_pull_at TEXT)''');
              // Create stubs for other syncable tables to avoid query errors
              for (final t in ['baby','caregiver','pump_session','stash_bottle',
                               'diaper','sleep','vaccination','daily_note']) {
                await db.execute('CREATE TABLE $t (id TEXT PRIMARY KEY, deleted_at TEXT)');
              }
            },
          ));

      server = FakeSupabaseServer();
      cursors = SyncCursorsDao(db: db);
    });

    tearDown(() => db.close());

    test('verify() returns true when counts match', () async {
      // Arrange: server has 2 feed rows; local DB has 2 feed rows
      server.encryptedRows.add(FakeEncryptedRow(
        id: 'a', familyId: 'fam-1', tableName: 'feed', recordId: 'a',
        version: 1, keyVersion: 1,
        ciphertext: Uint8List(0), aadHash: Uint8List(0),
        writtenByDevice: 'dev', updatedAt: DateTime.now(),
      ));
      server.encryptedRows.add(FakeEncryptedRow(
        id: 'b', familyId: 'fam-1', tableName: 'feed', recordId: 'b',
        version: 1, keyVersion: 1,
        ciphertext: Uint8List(0), aadHash: Uint8List(0),
        writtenByDevice: 'dev', updatedAt: DateTime.now(),
      ));
      await db.insert('feed', {'id': 'a', 'baby_id': 'b1', 'started_at': 'now', 'ended_at': null, 'feed_type': 'bottle', 'amount_oz': 4.0, 'side': null, 'note': null, 'deleted_at': null, 'version': 1, 'dirty': 0});
      await db.insert('feed', {'id': 'b', 'baby_id': 'b1', 'started_at': 'now', 'ended_at': null, 'feed_type': 'bottle', 'amount_oz': 3.0, 'side': null, 'note': null, 'deleted_at': null, 'version': 1, 'dirty': 0});

      final attestation = CountAttestation(
        db: db, server: server, cursors: cursors, familyId: 'fam-1',
      );
      final ok = await attestation.verify();
      expect(ok, isTrue);
    });

    test('verify() resets cursor + reports diff on mismatch', () async {
      // Server has 2 feed rows, local has 1
      server.encryptedRows.add(FakeEncryptedRow(
        id: 'a', familyId: 'fam-1', tableName: 'feed', recordId: 'a',
        version: 1, keyVersion: 1,
        ciphertext: Uint8List(0), aadHash: Uint8List(0),
        writtenByDevice: 'dev', updatedAt: DateTime.now(),
      ));
      server.encryptedRows.add(FakeEncryptedRow(
        id: 'b', familyId: 'fam-1', tableName: 'feed', recordId: 'b',
        version: 1, keyVersion: 1,
        ciphertext: Uint8List(0), aadHash: Uint8List(0),
        writtenByDevice: 'dev', updatedAt: DateTime.now(),
      ));
      await db.insert('feed', {'id': 'a', 'baby_id': 'b1', 'started_at': 'now', 'ended_at': null, 'feed_type': 'bottle', 'amount_oz': 4.0, 'side': null, 'note': null, 'deleted_at': null, 'version': 1, 'dirty': 0});
      // Advance cursor so we confirm it gets reset
      await cursors.writeLastPullAt('fam-1', DateTime.now().toUtc());

      Map<String, (int, int)>? captured;
      final attestation = CountAttestation(
        db: db,
        server: server,
        cursors: cursors,
        familyId: 'fam-1',
        onMismatch: (diff) => captured = diff,
      );
      final ok = await attestation.verify();
      expect(ok, isFalse);
      expect(captured, isNotNull);
      expect(captured!['feed'], equals((1, 2)));
      expect(await cursors.readLastPullAt('fam-1'), isNull);
    });
  });
}
