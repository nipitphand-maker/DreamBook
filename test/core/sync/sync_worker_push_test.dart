import 'dart:typed_data';

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
import 'package:dreambook/core/sync/sync_error.dart';
import 'package:dreambook/core/sync/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../_fakes/fake_supabase_server.dart';
import '../../_fakes/in_memory_secure_storage.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  late Database db;
  late FakeSupabaseServer server;
  late FamilyKeyService familyKeys;
  late SyncWorker worker;
  const familyId = 'fam-1';
  const deviceFp = 'device-A';

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
    server = FakeSupabaseServer();
    server.families[familyId] = FakeFamily(id: familyId);
    server.devices[deviceFp] = FakeDevice(
      deviceFp: deviceFp,
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
      deviceFp: deviceFp,
    );
  });

  tearDown(() async {
    server.dispose();
    await db.close();
  });

  Future<void> seedDirtyFeedRow() async {
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
    await db.insert('feed', {
      'id': 'feed-1',
      'baby_id': 'b1',
      'started_at': '2026-05-14T08:00:00.000Z',
      'type': 'bottle',
      'oz': 4.0,
      'note': null,
      'created_at': '2026-05-14T08:00:00.000Z',
      'updated_at': '2026-05-14T08:00:00.000Z',
      'version': 1,
      'family_id': familyId,
      'key_version': 1,
    });
    await db.insert('sync_state', {
      'record_id': 'feed-1',
      'table_name': 'feed',
      'version': 1,
      'updated_at': '2026-05-14T08:00:00.000Z',
      'dirty': 1,
      'last_synced_at': null,
    });
  }

  group('SyncWorker.pushOnce', () {
    test('seals dirty row, uploads ciphertext, clears dirty flag', () async {
      await seedDirtyFeedRow();
      await worker.pushOnce();
      expect(server.encryptedRows.length, 1);
      final uploaded = server.encryptedRows.first;
      expect(uploaded.tableName, 'feed');
      expect(uploaded.recordId, 'feed-1');
      expect(uploaded.version, 1);
      expect(uploaded.keyVersion, 1);
      expect(uploaded.writtenByDevice, deviceFp);
      expect(uploaded.ciphertext.length, greaterThan(28));
      final state = await db.query(
        'sync_state',
        where: 'record_id = ?',
        whereArgs: ['feed-1'],
      );
      expect(state.first['dirty'], 0);
      expect(state.first['last_synced_at'], isNotNull);
    });

    test('network failure leaves row dirty for retry', () async {
      await seedDirtyFeedRow();
      server.simulateNetworkError = true;
      await expectLater(
        () => worker.pushOnce(),
        throwsA(isA<SyncNetworkError>()),
      );
      final state = await db.query(
        'sync_state',
        where: 'record_id = ?',
        whereArgs: ['feed-1'],
      );
      expect(state.first['dirty'], 1);
      expect(state.first['last_synced_at'], isNull);
    });

    test('RLS reject (403) throws SyncRlsReject and stops worker', () async {
      await seedDirtyFeedRow();
      server.devices[deviceFp]!.revokedAt = DateTime.now().toUtc();
      await expectLater(
        () => worker.pushOnce(),
        throwsA(isA<SyncRlsReject>()),
      );
    });

    test('no dirty rows → pushOnce is a no-op (idempotent)', () async {
      await seedDirtyFeedRow();
      await worker.pushOnce();
      await worker.pushOnce(); // second call
      expect(server.encryptedRows.length, 1);
    });
  });
}
