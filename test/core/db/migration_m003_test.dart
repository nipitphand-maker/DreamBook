import 'package:dreambook/core/db/migrations/m001_initial.dart';
import 'package:dreambook/core/db/migrations/m002_v2.dart';
import 'package:dreambook/core/db/migrations/m003_v3.dart';
import 'package:dreambook/core/db/migrations/migrations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (d, _) async {
          await Migrations([m001Initial, m002V2]).runAll(d);
        },
      ),
    );
  });

  tearDown(() => db.close());

  test('adds family_id and key_version columns to every syncable table', () async {
    await m003V3(db);
    final tables = [
      'baby', 'caregiver', 'pump_session', 'stash_bottle',
      'feed', 'diaper', 'sleep', 'vaccination',
    ];
    for (final t in tables) {
      final info = await db.rawQuery('PRAGMA table_info($t)');
      final cols = info.map((r) => r['name'] as String).toSet();
      expect(cols, contains('family_id'),
          reason: 'family_id missing on $t');
      expect(cols, contains('key_version'),
          reason: 'key_version missing on $t');
    }
  });

  test('creates family_metadata + key_rotation_state tables', () async {
    await m003V3(db);
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    final names = tables.map((r) => r['name'] as String).toSet();
    expect(names, contains('family_metadata'));
    expect(names, contains('key_rotation_state'));
  });

  test('backfills existing rows with same family_id from family_metadata', () async {
    await db.insert('baby', {
      'id': 'b1',
      'name': 'Mali',
      'dob': '2026-03-01',
      'preferred_unit': 'oz',
      'created_at': '2026-05-13T00:00:00.000Z',
      'updated_at': '2026-05-13T00:00:00.000Z',
      'version': 1,
    });
    await m003V3(db);
    final meta = await db.query('family_metadata');
    expect(meta.length, 1);
    final familyId = meta.first['id'] as String;
    final babies = await db.query('baby');
    expect(babies.first['family_id'], familyId);
    expect(babies.first['key_version'], 1);
  });
}
