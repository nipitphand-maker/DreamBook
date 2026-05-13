import 'package:dreambook/core/db/migrations/m001_initial.dart';
import 'package:dreambook/core/db/migrations/m002_v2.dart';
import 'package:dreambook/core/db/migrations/migrations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  Future<Database> openMem() async {
    return databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 2, onCreate: (db, _) async {
        await Migrations([m001Initial, m002V2]).runAll(db);
      }),
    );
  }

  test('v1 creates 9 user tables + sync_state + meta', () async {
    final db = await openMem();
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%' ORDER BY name",
    );
    final names = rows.map((r) => r['name']).toSet();
    expect(names, containsAll(<String>{
      'baby', 'caregiver', 'diaper', 'feed', 'meta',
      'pump_session', 'sleep', 'stash_bottle', 'sync_state', 'vaccination',
    }));
    await db.close();
  });

  test('foreign keys cascade on baby delete', () async {
    final db = await openMem();
    await db.execute('PRAGMA foreign_keys = ON');
    await db.insert('baby', {
      'id': 'b1',
      'name': 'Mali',
      'dob': '2026-03-01',
      'preferred_unit': 'oz',
      'created_at': '2026-05-13T00:00:00Z',
      'updated_at': '2026-05-13T00:00:00Z',
      'version': 1,
    });
    await db.insert('feed', {
      'id': 'f1',
      'baby_id': 'b1',
      'type': 'breast',
      'side': 'left',
      'started_at': '2026-05-13T00:00:00Z',
      'created_at': '2026-05-13T00:00:00Z',
      'updated_at': '2026-05-13T00:00:00Z',
      'version': 1,
    });
    await db.delete('baby', where: 'id = ?', whereArgs: ['b1']);
    final remaining = await db.query('feed');
    expect(remaining, isEmpty);
    await db.close();
  });

  test('check constraints reject invalid enum values', () async {
    final db = await openMem();
    expect(
      () => db.insert('baby', {
        'id': 'b1',
        'name': 'Mali',
        'dob': '2026-03-01',
        'sex': 'banana',
        'preferred_unit': 'oz',
        'created_at': '2026-05-13T00:00:00Z',
        'updated_at': '2026-05-13T00:00:00Z',
        'version': 1,
      }),
      throwsA(isA<DatabaseException>()),
    );
    await db.close();
  });

  test('v2 adds thawed_at + parent_bottle_id + source to stash_bottle', () async {
    final db = await openMem();
    final cols = await db.rawQuery('PRAGMA table_info(stash_bottle)');
    final names = cols.map((r) => r['name'] as String).toSet();
    expect(names, containsAll({'thawed_at', 'parent_bottle_id', 'source'}));
    await db.close();
  });

  test('v2 adds paused_duration_min to pump_session with default 0', () async {
    final db = await openMem();
    final cols = await db.rawQuery('PRAGMA table_info(pump_session)');
    final pausedCol = cols.firstWhere((r) => r['name'] == 'paused_duration_min');
    expect(pausedCol['dflt_value'], '0');
    expect(pausedCol['notnull'], 1);
    await db.close();
  });
}
