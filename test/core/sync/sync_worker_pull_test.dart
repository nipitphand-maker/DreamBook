import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dreambook/core/crypto/crypto_envelope.dart';
import 'package:dreambook/core/crypto/family_key_service.dart';
import 'package:dreambook/core/db/migrations/m001_initial.dart';
import 'package:dreambook/core/db/migrations/m002_v2.dart';
import 'package:dreambook/core/db/migrations/m003_v3.dart';
import 'package:dreambook/core/db/migrations/m004_v4.dart';
import 'package:dreambook/core/db/migrations/m005_daily_note.dart';
import 'package:dreambook/core/db/migrations/m006_sync_written_by.dart';
import 'package:dreambook/core/db/migrations/m007_sync_cursors.dart';
import 'package:dreambook/core/db/migrations/migrations.dart';
import 'package:dreambook/core/sync/encrypted_row.dart';
import 'package:dreambook/core/sync/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../_fakes/fake_supabase_server.dart';
import '../../_fakes/in_memory_secure_storage.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  late Database db;
  late FakeSupabaseServer server;
  late FamilyKeyService familyKeys;
  late SyncWorker worker;
  const familyId = 'fam-1';
  const localDeviceFp = 'device-A';
  const remoteDeviceFp = 'device-B';

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 7,
        onCreate: (d, _) async {
          await Migrations([m001Initial, m002V2, m003V3, m004V4, m005DailyNote, m006SyncWrittenBy, m007SyncCursors]).runAll(d);
        },
      ),
    );
    await db.execute('PRAGMA foreign_keys = ON');
    await db.insert('family_metadata', {
      'id': familyId,
      'current_key_version': 1,
      'created_at': '2026-05-14T00:00:00.000Z',
    });
    await db.insert('baby', {
      'id': 'b1',
      'name': 'Mali',
      'dob': '2026-03-01',
      'preferred_unit': 'oz',
      'created_at': '2026-05-14T00:00:00.000Z',
      'updated_at': '2026-05-14T00:00:00.000Z',
      'version': 1,
      'family_id': familyId,
      'key_version': 1,
    });
    server = FakeSupabaseServer();
    server.families[familyId] = FakeFamily(id: familyId);
    server.devices[localDeviceFp] = FakeDevice(
      deviceFp: localDeviceFp,
      familyId: familyId,
      devicePubKey: Uint8List(32),
      role: 'admin',
      keyVersionAtJoin: 1,
    );
    familyKeys = FamilyKeyService.forTest(InMemorySecureStorage());
    await familyKeys.generate(familyId: familyId, keyVersion: 1);
    worker = SyncWorker(
      db: db,
      server: server,
      familyKeys: familyKeys,
      envelope: CryptoEnvelope(),
      familyId: familyId,
      deviceFp: localDeviceFp,
    );
  });

  tearDown(() async {
    server.dispose();
    await db.close();
  });

  /// Builds + injects a FakeEncryptedRow as if Device B had pushed it.
  Future<FakeEncryptedRow> seedRow({
    required String recordId,
    required int version,
    String? noteOverride,
  }) async {
    final key = (await familyKeys.read(familyId: familyId))!;
    final plaintext = {
      'id': recordId,
      'baby_id': 'b1',
      'started_at': '2026-05-14T09:00:00.000Z',
      'type': 'breast',
      'oz': null,
      'note': noteOverride ?? 'pull-test',
      'created_at': '2026-05-14T09:00:00.000Z',
      'updated_at': '2026-05-14T09:00:00.000Z',
      'version': version,
      'family_id': familyId,
      'key_version': 1,
      'deleted_at': null,
    };
    final aad = EncryptedRow.aadFor(
      tableName: 'feed',
      recordId: recordId,
      version: version,
      familyId: familyId,
      keyVersion: 1,
    );
    final envelope = CryptoEnvelope();
    final ct = await envelope.seal(
      utf8.encode(jsonEncode(plaintext)),
      SecretKey(key.bytes),
      utf8.encode(aad),
    );
    final aadHash = Uint8List.fromList(
      (await Blake2b().hash(utf8.encode(aad))).bytes,
    );
    final row = FakeEncryptedRow(
      id: const Uuid().v4(),
      familyId: familyId,
      tableName: 'feed',
      recordId: recordId,
      version: version,
      keyVersion: 1,
      ciphertext: ct,
      aadHash: aadHash,
      writtenByDevice: remoteDeviceFp,
      updatedAt: DateTime.now().toUtc(),
    );
    server.encryptedRows.add(row);
    return row;
  }

  group('SyncWorker.pullOnce', () {
    test('decrypts incoming row and upserts to local feed table', () async {
      await seedRow(recordId: 'feed-r1', version: 1);
      await worker.pullOnce();
      final rows = await db.query('feed');
      expect(rows.length, 1);
      expect(rows.first['id'], 'feed-r1');
      expect(rows.first['note'], 'pull-test');
    });

    test('pulled rows do NOT mark sync_state.dirty', () async {
      await seedRow(recordId: 'feed-r2', version: 1);
      await worker.pullOnce();
      final dirty = await db.query('sync_state', where: 'dirty = 1');
      expect(dirty, isEmpty);
    });

    test('tampered aad_hash row is discarded, no upsert', () async {
      final row = await seedRow(recordId: 'feed-tamper', version: 1);
      // Corrupt aad_hash in place after it's already in the server list.
      row.aadHash[0] ^= 0xFF;
      await worker.pullOnce();
      final rows = await db.query('feed', where: 'id = ?', whereArgs: ['feed-tamper']);
      expect(rows, isEmpty);
    });

    test('wrong-key row does not abort the loop; valid rows still flow', () async {
      // Seal a row under a totally different key.
      final aad = EncryptedRow.aadFor(
        tableName: 'feed',
        recordId: 'feed-bad',
        version: 1,
        familyId: familyId,
        keyVersion: 1,
      );
      final otherKey = await AesGcm.with256bits().newSecretKey();
      final ct = await CryptoEnvelope().seal(
        utf8.encode(jsonEncode({'id': 'feed-bad'})),
        otherKey,
        utf8.encode(aad),
      );
      server.encryptedRows.add(FakeEncryptedRow(
        id: const Uuid().v4(),
        familyId: familyId,
        tableName: 'feed',
        recordId: 'feed-bad',
        version: 1,
        keyVersion: 1,
        ciphertext: ct,
        aadHash: Uint8List.fromList(
          (await Blake2b().hash(utf8.encode(aad))).bytes,
        ),
        writtenByDevice: remoteDeviceFp,
        updatedAt: DateTime.now().toUtc(),
      ));
      await seedRow(recordId: 'feed-ok', version: 1);
      await worker.pullOnce();
      final ok = await db.query('feed', where: 'id = ?', whereArgs: ['feed-ok']);
      expect(ok, isNotEmpty);
      final bad = await db.query('feed', where: 'id = ?', whereArgs: ['feed-bad']);
      expect(bad, isEmpty);
    });

    test('same-version row with older updated_at is rejected (LWW)', () async {
      // b1 baby already seeded in setUp
      await db.insert('feed', {
        'id': 'conflict-feed',
        'baby_id': 'b1',
        'type': 'breast',
        'started_at': '2026-05-14T09:00:00.000Z',
        'note': 'local-note',
        'created_at': '2026-05-14T09:00:00.000Z',
        'updated_at': '2026-05-14T10:00:00.000Z', // local is NEWER
        'version': 1,
        'family_id': familyId,
        'key_version': 1,
      });
      await db.insert('sync_state', {
        'record_id': 'conflict-feed',
        'table_name': 'feed',
        'version': 1,
        'updated_at': '2026-05-14T10:00:00.000Z',
        'dirty': 0,
        'last_synced_at': '2026-05-14T10:00:00.000Z',
        'written_by_device': localDeviceFp,
      });

      // Remote row has same version but older updated_at — local should win
      final key = (await familyKeys.read(familyId: familyId))!;
      final plaintext = {
        'id': 'conflict-feed',
        'baby_id': 'b1',
        'type': 'breast',
        'started_at': '2026-05-14T09:00:00.000Z',
        'note': 'remote-note',
        'created_at': '2026-05-14T09:00:00.000Z',
        'updated_at': '2026-05-14T08:00:00.000Z', // remote is OLDER
        'version': 1,
        'family_id': familyId,
        'key_version': 1,
        'deleted_at': null,
      };
      final aad = EncryptedRow.aadFor(
        tableName: 'feed', recordId: 'conflict-feed',
        version: 1, familyId: familyId, keyVersion: 1,
      );
      final ct = await CryptoEnvelope().seal(
        utf8.encode(jsonEncode(plaintext)),
        SecretKey(key.bytes), utf8.encode(aad),
      );
      final aadHash = Uint8List.fromList(
        (await Blake2b().hash(utf8.encode(aad))).bytes,
      );
      server.encryptedRows.add(FakeEncryptedRow(
        id: const Uuid().v4(),
        familyId: familyId, tableName: 'feed',
        recordId: 'conflict-feed', version: 1, keyVersion: 1,
        ciphertext: ct, aadHash: aadHash,
        writtenByDevice: remoteDeviceFp,
        updatedAt: DateTime.now().toUtc(),
      ));

      await worker.pullOnce();
      final rows = await db.query('feed', where: "id = 'conflict-feed'");
      expect(rows.first['note'], 'local-note'); // local wins
    });

    test('same-version row with newer updated_at replaces local (LWW)', () async {
      await db.insert('feed', {
        'id': 'conflict-feed2',
        'baby_id': 'b1',
        'type': 'breast',
        'started_at': '2026-05-14T09:00:00.000Z',
        'note': 'stale-local',
        'created_at': '2026-05-14T09:00:00.000Z',
        'updated_at': '2026-05-14T08:00:00.000Z', // local is OLDER
        'version': 1,
        'family_id': familyId,
        'key_version': 1,
      });
      await db.insert('sync_state', {
        'record_id': 'conflict-feed2',
        'table_name': 'feed',
        'version': 1,
        'updated_at': '2026-05-14T08:00:00.000Z',
        'dirty': 0,
        'last_synced_at': '2026-05-14T08:00:00.000Z',
        'written_by_device': localDeviceFp,
      });

      final key = (await familyKeys.read(familyId: familyId))!;
      final plaintext = {
        'id': 'conflict-feed2',
        'baby_id': 'b1',
        'type': 'breast',
        'started_at': '2026-05-14T09:00:00.000Z',
        'note': 'fresh-remote',
        'created_at': '2026-05-14T09:00:00.000Z',
        'updated_at': '2026-05-14T10:00:00.000Z', // remote is NEWER
        'version': 1,
        'family_id': familyId,
        'key_version': 1,
        'deleted_at': null,
      };
      final aad = EncryptedRow.aadFor(
        tableName: 'feed', recordId: 'conflict-feed2',
        version: 1, familyId: familyId, keyVersion: 1,
      );
      final ct = await CryptoEnvelope().seal(
        utf8.encode(jsonEncode(plaintext)),
        SecretKey(key.bytes), utf8.encode(aad),
      );
      final aadHash = Uint8List.fromList(
        (await Blake2b().hash(utf8.encode(aad))).bytes,
      );
      server.encryptedRows.add(FakeEncryptedRow(
        id: const Uuid().v4(),
        familyId: familyId, tableName: 'feed',
        recordId: 'conflict-feed2', version: 1, keyVersion: 1,
        ciphertext: ct, aadHash: aadHash,
        writtenByDevice: remoteDeviceFp,
        updatedAt: DateTime.now().toUtc(),
      ));

      await worker.pullOnce();
      final rows = await db.query('feed', where: "id = 'conflict-feed2'");
      expect(rows.first['note'], 'fresh-remote'); // remote wins
    });
  });

  group('SyncWorker cursor persistence (sync_cursors)', () {
    test('fresh family — no cursor row, since is null on first pull', () async {
      // Empty server, no cursor seeded.
      await worker.pullOnce();
      // sync_cursors stays empty when nothing was pulled.
      final cursors = await db.query('sync_cursors');
      expect(cursors, isEmpty);
      expect(worker.debugLastPullAt, isNull);
    });

    test('successful pull persists max(updated_at) to sync_cursors', () async {
      await seedRow(recordId: 'feed-cursor-a', version: 1);
      await worker.pullOnce();
      final cursors = await db.query('sync_cursors', where: 'family_id = ?', whereArgs: [familyId]);
      expect(cursors, hasLength(1));
      final persisted = DateTime.parse(cursors.first['last_pull_at'] as String);
      // Should equal the row's updatedAt we set in seedRow.
      expect(persisted.isAtSameMomentAs(worker.debugLastPullAt!), isTrue);
    });

    test('cold-start reads cursor from sync_cursors and pulls incrementally', () async {
      // Seed an existing cursor as if a previous launch had persisted it.
      final priorCursor = DateTime.utc(2026, 5, 14, 12);
      await db.insert('sync_cursors', {
        'family_id': familyId,
        'last_pull_at': priorCursor.toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      // Build a fresh worker (simulates cold start: in-memory cache empty).
      final freshWorker = SyncWorker(
        db: db,
        server: server,
        familyKeys: familyKeys,
        envelope: CryptoEnvelope(),
        familyId: familyId,
        deviceFp: localDeviceFp,
      );
      expect(freshWorker.debugLastPullAt, isNull); // not yet hydrated
      await freshWorker.pullOnce();
      // After first pull, in-memory cursor matches persisted value (no new rows).
      expect(freshWorker.debugLastPullAt, isNotNull);
      expect(
        freshWorker.debugLastPullAt!.isAtSameMomentAs(priorCursor),
        isTrue,
      );
      // FakeSupabaseServer filters with `updatedAt.isAfter(since)` — confirm
      // we passed the persisted cursor through (a row stamped at priorCursor
      // is excluded; only strictly newer rows would flow).
      // Add a row equal to priorCursor; it must NOT come through.
      final key = (await familyKeys.read(familyId: familyId))!;
      final aad = EncryptedRow.aadFor(
        tableName: 'feed',
        recordId: 'feed-at-cursor',
        version: 1,
        familyId: familyId,
        keyVersion: 1,
      );
      final ct = await CryptoEnvelope().seal(
        utf8.encode(jsonEncode({
          'id': 'feed-at-cursor',
          'baby_id': 'b1',
          'type': 'breast',
          'started_at': '2026-05-14T09:00:00.000Z',
          'note': 'at-cursor',
          'created_at': '2026-05-14T09:00:00.000Z',
          'updated_at': priorCursor.toIso8601String(),
          'version': 1,
          'family_id': familyId,
          'key_version': 1,
          'deleted_at': null,
        })),
        SecretKey(key.bytes),
        utf8.encode(aad),
      );
      server.encryptedRows.add(FakeEncryptedRow(
        id: const Uuid().v4(),
        familyId: familyId,
        tableName: 'feed',
        recordId: 'feed-at-cursor',
        version: 1,
        keyVersion: 1,
        ciphertext: ct,
        aadHash: Uint8List.fromList(
          (await Blake2b().hash(utf8.encode(aad))).bytes,
        ),
        writtenByDevice: remoteDeviceFp,
        updatedAt: priorCursor, // exactly equal — must be filtered out
      ));
      await freshWorker.pullOnce();
      final feed = await db.query('feed', where: "id = 'feed-at-cursor'");
      expect(feed, isEmpty, reason: 'row at cursor boundary must be excluded');
    });

    test('cursor advances monotonically across pulls', () async {
      final t1 = DateTime.utc(2026, 5, 14, 9);
      final t2 = DateTime.utc(2026, 5, 14, 10);
      // First pull seeds at t1.
      final key = (await familyKeys.read(familyId: familyId))!;
      Future<void> addRow(String id, DateTime updatedAt) async {
        final aad = EncryptedRow.aadFor(
          tableName: 'feed',
          recordId: id,
          version: 1,
          familyId: familyId,
          keyVersion: 1,
        );
        final ct = await CryptoEnvelope().seal(
          utf8.encode(jsonEncode({
            'id': id,
            'baby_id': 'b1',
            'type': 'breast',
            'started_at': '2026-05-14T09:00:00.000Z',
            'note': 'monotone',
            'created_at': '2026-05-14T09:00:00.000Z',
            'updated_at': updatedAt.toIso8601String(),
            'version': 1,
            'family_id': familyId,
            'key_version': 1,
            'deleted_at': null,
          })),
          SecretKey(key.bytes),
          utf8.encode(aad),
        );
        server.encryptedRows.add(FakeEncryptedRow(
          id: const Uuid().v4(),
          familyId: familyId,
          tableName: 'feed',
          recordId: id,
          version: 1,
          keyVersion: 1,
          ciphertext: ct,
          aadHash: Uint8List.fromList(
            (await Blake2b().hash(utf8.encode(aad))).bytes,
          ),
          writtenByDevice: remoteDeviceFp,
          updatedAt: updatedAt,
        ));
      }

      await addRow('mon-1', t1);
      await worker.pullOnce();
      final c1 = (await db.query('sync_cursors',
              where: 'family_id = ?', whereArgs: [familyId]))
          .first['last_pull_at'] as String;
      expect(DateTime.parse(c1).isAtSameMomentAs(t1), isTrue);

      await addRow('mon-2', t2);
      await worker.pullOnce();
      final c2 = (await db.query('sync_cursors',
              where: 'family_id = ?', whereArgs: [familyId]))
          .first['last_pull_at'] as String;
      expect(DateTime.parse(c2).isAtSameMomentAs(t2), isTrue);
      // Only one cursor row per family (PK enforced).
      final all = await db.query('sync_cursors');
      expect(all, hasLength(1));
    });
  });
}
