import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dreambook/core/crypto/crypto_envelope.dart';
import 'package:dreambook/core/crypto/family_key_service.dart';
import 'package:dreambook/core/crypto/key_rotation_service.dart';
import 'package:dreambook/core/db/migrations/m001_initial.dart';
import 'package:dreambook/core/db/migrations/m002_v2.dart';
import 'package:dreambook/core/db/migrations/m003_v3.dart';
import 'package:dreambook/core/db/migrations/migrations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../_fakes/fake_supabase_server.dart';
import '../../_fakes/in_memory_secure_storage.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  group('KeyRotationService — network rotation (Task 16)', () {
    late Database db;
    late FakeSupabaseServer server;
    late FamilyKeyService familyKeys;
    const familyId = 'fam-1';
    const adminFp = 'device-admin';
    const survivorFp = 'device-survivor';
    const revokedFp = 'device-revoked';

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
      await db.insert('family_metadata', {
        'id': familyId,
        'current_key_version': 1,
        'created_at': '2026-05-14T00:00:00.000Z',
      });
      server = FakeSupabaseServer();
      server.families[familyId] = FakeFamily(id: familyId);
      familyKeys = FamilyKeyService.forTest(InMemorySecureStorage());
      await familyKeys.generate(familyId: familyId, keyVersion: 1);
    });

    tearDown(() async {
      server.dispose();
      await db.close();
    });

    test(
      'rotation: revoked device is marked, survivor receives K_v2 envelope, '
      'local key_version bumps to 2',
      () async {
        // Admin's X25519 key pair (the caller).
        final x = X25519();
        final adminPair = await x.newKeyPair();
        final adminPub = await adminPair.extractPublicKey();
        final survivorPair = await x.newKeyPair();
        final survivorPub = await survivorPair.extractPublicKey();
        final revokedPair = await x.newKeyPair();
        final revokedPub = await revokedPair.extractPublicKey();

        server.devices[adminFp] = FakeDevice(
          deviceFp: adminFp,
          familyId: familyId,
          devicePubKey: Uint8List.fromList(adminPub.bytes),
          role: 'admin',
          keyVersionAtJoin: 1,
        );
        server.devices[survivorFp] = FakeDevice(
          deviceFp: survivorFp,
          familyId: familyId,
          devicePubKey: Uint8List.fromList(survivorPub.bytes),
          role: 'editor',
          keyVersionAtJoin: 1,
        );
        server.devices[revokedFp] = FakeDevice(
          deviceFp: revokedFp,
          familyId: familyId,
          devicePubKey: Uint8List.fromList(revokedPub.bytes),
          role: 'editor',
          keyVersionAtJoin: 1,
        );

        final service = KeyRotationService(
          db: db,
          familyKeys: familyKeys,
          server: server,
          callerDeviceFp: adminFp,
          ourKeyPair: adminPair,
        );

        await service.rotateRevokeAndFanOut(
          familyId: familyId,
          targetDeviceFp: revokedFp,
        );

        // Server state: target marked revoked, family version bumped.
        expect(server.devices[revokedFp]!.revokedAt, isNotNull);
        expect(server.devices[revokedFp]!.wipeRequestedAt, isNotNull);
        expect(server.families[familyId]!.currentKeyVersion, 2);

        // Survivor (and only survivor) has a key_distribution row for v2.
        final survivorRows = server.keyDistribution
            .where((r) =>
                r.recipientDeviceFp == survivorFp && r.keyVersion == 2)
            .toList();
        expect(survivorRows, hasLength(1));
        expect(
          server.keyDistribution
              .where((r) => r.recipientDeviceFp == revokedFp)
              .toList(),
          isEmpty,
        );

        // The wrapped envelope must decrypt for the survivor with the
        // admin's public key + survivor's private key.
        final shared = await x.sharedSecretKey(
          keyPair: survivorPair,
          remotePublicKey: adminPub,
        );
        final plaintext = await CryptoEnvelope().open(
          survivorRows.first.wrappedKey,
          shared,
          utf8.encode('$familyId|2'),
        );
        final newLocalKey = await familyKeys.read(familyId: familyId);
        expect(newLocalKey, isNotNull);
        expect(plaintext, equals(newLocalKey!.bytes));

        // Local DB state: version bumped to 2, rotation state cleared.
        final meta = await db.query(
          'family_metadata',
          where: 'id = ?',
          whereArgs: [familyId],
        );
        expect(meta.first['current_key_version'], 2);
        final state = await db.query(
          'key_rotation_state',
          where: 'family_id = ?',
          whereArgs: [familyId],
        );
        expect(state, isEmpty);
      },
    );

    test(
      'mid-rotation crash: resumeIfNeeded() finishes the in-flight rotation',
      () async {
        // Simulate a crash AFTER server revoke + beginRotation but BEFORE
        // completeRotation. The server already shows v=2, but the local
        // DB still says v=1 with a key_rotation_state row.
        server.families[familyId]!.currentKeyVersion = 2;
        await db.insert('key_rotation_state', {
          'family_id': familyId,
          'target_key_version': 2,
          'started_at': '2026-05-14T00:00:00.000Z',
          'last_processed_row': null,
        });

        // Fresh service models a new app launch — no server/keyPair
        // needed for local resume.
        final fresh = KeyRotationService(db: db, familyKeys: familyKeys);
        await fresh.resumeIfNeeded(familyId: familyId);

        final meta = await db.query(
          'family_metadata',
          where: 'id = ?',
          whereArgs: [familyId],
        );
        expect(meta.first['current_key_version'], 2);
        final state = await db.query(
          'key_rotation_state',
          where: 'family_id = ?',
          whereArgs: [familyId],
        );
        expect(state, isEmpty);
        final stored = await familyKeys.read(familyId: familyId);
        expect(stored!.keyVersion, 2);
      },
    );
  });
}
