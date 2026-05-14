import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dreambook/core/crypto/crypto_envelope.dart';
import 'package:dreambook/core/crypto/family_key_service.dart';
import 'package:dreambook/core/db/migrations/m001_initial.dart';
import 'package:dreambook/core/db/migrations/m002_v2.dart';
import 'package:dreambook/core/db/migrations/m003_v3.dart';
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
        version: 3,
        onCreate: (d, _) async {
          await Migrations([m001Initial, m002V2, m003V3]).runAll(d);
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
  });
}
