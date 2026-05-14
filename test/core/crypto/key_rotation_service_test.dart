import 'package:dreambook/core/crypto/family_key_service.dart';
import 'package:dreambook/core/crypto/key_rotation_service.dart';
import 'package:dreambook/core/db/migrations/m001_initial.dart';
import 'package:dreambook/core/db/migrations/m002_v2.dart';
import 'package:dreambook/core/db/migrations/m003_v3.dart';
import 'package:dreambook/core/db/migrations/migrations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../_fakes/in_memory_secure_storage.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  late Database db;
  late FamilyKeyService familyKeys;
  late KeyRotationService service;
  const familyId = 'fam-1';

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
    familyKeys = FamilyKeyService.forTest(InMemorySecureStorage());
    await familyKeys.generate(familyId: familyId, keyVersion: 1);
    await db.insert('family_metadata', {
      'id': familyId,
      'current_key_version': 1,
      'created_at': '2026-05-14T00:00:00.000Z',
    });
    service = KeyRotationService(db: db, familyKeys: familyKeys);
  });

  tearDown(() => db.close());

  group('KeyRotationService', () {
    test('beginRotation() writes key_rotation_state and bumps target version', () async {
      await service.beginRotation(familyId: familyId);
      final rows = await db.query('key_rotation_state', where: 'family_id = ?', whereArgs: [familyId]);
      expect(rows.length, 1);
      expect(rows.first['target_key_version'], 2);
    });

    test('completeRotation() updates family_metadata version and clears state', () async {
      await service.beginRotation(familyId: familyId);
      await service.completeRotation(familyId: familyId);
      final meta = await db.query('family_metadata', where: 'id = ?', whereArgs: [familyId]);
      expect(meta.first['current_key_version'], 2);
      final state = await db.query('key_rotation_state', where: 'family_id = ?', whereArgs: [familyId]);
      expect(state, isEmpty);
      final newKey = await familyKeys.read(familyId: familyId);
      expect(newKey!.keyVersion, 2);
    });

    test('resume() picks up an interrupted rotation and finishes it', () async {
      await service.beginRotation(familyId: familyId);
      // Simulate crash: do NOT call completeRotation.
      // New service instance models a fresh app launch.
      final fresh = KeyRotationService(db: db, familyKeys: familyKeys);
      await fresh.resumeIfNeeded(familyId: familyId);
      final meta = await db.query('family_metadata', where: 'id = ?', whereArgs: [familyId]);
      expect(meta.first['current_key_version'], 2);
      final state = await db.query('key_rotation_state', where: 'family_id = ?', whereArgs: [familyId]);
      expect(state, isEmpty);
    });
  });
}
