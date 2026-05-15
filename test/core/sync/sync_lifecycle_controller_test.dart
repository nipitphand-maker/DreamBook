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
import 'package:dreambook/core/sync/sync_lifecycle_controller.dart';
import 'package:dreambook/core/sync/sync_status_provider.dart';
import 'package:dreambook/core/sync/sync_worker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../_fakes/fake_supabase_server.dart';
import '../../_fakes/in_memory_secure_storage.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  test('syncNow drives status from inFlight → completed with lastSyncedAt',
      () async {
    const familyId = 'fam-lifecycle';
    const deviceFp = 'device-life';

    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 7,
        onCreate: (d, _) async {
          await Migrations([
            m001Initial,
            m002V2,
            m003V3,
            m004V4,
            m005DailyNote,
            m006SyncWrittenBy,
            m007SyncCursors,
          ]).runAll(d);
        },
      ),
    );
    await db.execute('PRAGMA foreign_keys = ON');
    await db.insert('family_metadata', {
      'id': familyId,
      'current_key_version': 1,
      'created_at': '2026-05-14T00:00:00.000Z',
    });

    final server = FakeSupabaseServer();
    server.families[familyId] = FakeFamily(id: familyId);
    server.devices[deviceFp] = FakeDevice(
      deviceFp: deviceFp,
      familyId: familyId,
      devicePubKey: Uint8List(32),
      role: 'admin',
      keyVersionAtJoin: 1,
    );

    final familyKeys = FamilyKeyService.forTest(InMemorySecureStorage());
    await familyKeys.generate(familyId: familyId, keyVersion: 1);

    final worker = SyncWorker(
      db: db,
      server: server,
      familyKeys: familyKeys,
      envelope: CryptoEnvelope(),
      familyId: familyId,
      deviceFp: deviceFp,
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = SyncLifecycleController.fromContainer(
      container: container,
      worker: worker,
    );

    // Sanity: status starts idle.
    expect(container.read(syncStatusProvider).inFlight, isFalse);
    expect(container.read(syncStatusProvider).lastSyncedAt, isNull);

    await controller.syncNow();

    final status = container.read(syncStatusProvider);
    expect(status.inFlight, isFalse);
    expect(status.lastSyncedAt, isNotNull);
    expect(status.lastError, isNull);

    server.dispose();
    await db.close();
  });
}
