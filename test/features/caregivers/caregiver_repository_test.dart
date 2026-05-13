import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/db/migrations/m001_initial.dart';
import 'package:dreambook/core/db/migrations/m002_v2.dart';
import 'package:dreambook/core/db/migrations/migrations.dart';
import 'package:dreambook/features/caregivers/data/caregiver_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  late Database db;
  late ProviderContainer container;

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
    await db.execute('PRAGMA foreign_keys = ON');
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((_) async => db),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  CaregiverRepository repo() => container.read(caregiverRepositoryProvider);

  test('getOrCreateSelf() creates a new self-caregiver on first call',
      () async {
    final c = await repo().getOrCreateSelf(deviceId: 'device-abc');

    expect(c.displayName, 'Me');
    expect(c.deviceId, 'device-abc');
    expect(c.revokedAt, isNull);
    expect(c.deletedAt, isNull);
    expect(c.version, 1);

    final rows = await db.query('caregiver');
    expect(rows.length, 1);
    expect(rows.first['display_name'], 'Me');
    expect(rows.first['device_id'], 'device-abc');
    expect(rows.first['revoked_at'], isNull);
    expect(rows.first['deleted_at'], isNull);
  });

  test(
      'getOrCreateSelf() returns the existing self-caregiver on subsequent calls (same device_id, same id)',
      () async {
    final a = await repo().getOrCreateSelf(deviceId: 'device-abc');
    final b = await repo().getOrCreateSelf(deviceId: 'device-abc');

    expect(b.id, a.id);
    expect(b.displayName, 'Me');
    expect(b.deviceId, 'device-abc');

    final rows = await db.query('caregiver');
    expect(rows.length, 1, reason: 'should not create a duplicate row');
  });

  test('getOrCreateSelf() writes sync_state dirty=1 only on the first call',
      () async {
    final c = await repo().getOrCreateSelf(deviceId: 'device-abc');

    // Flip dirty=0 to simulate a successful sync.
    await db.update(
      'sync_state',
      {'dirty': 0},
      where: 'record_id = ? AND table_name = ?',
      whereArgs: [c.id, 'caregiver'],
    );

    // Second call must not flip dirty back to 1 — the row already exists.
    await repo().getOrCreateSelf(deviceId: 'device-abc');

    final sync = await db.query(
      'sync_state',
      where: 'record_id = ? AND table_name = ?',
      whereArgs: [c.id, 'caregiver'],
    );
    expect(sync.length, 1);
    expect(sync.first['dirty'], 0,
        reason: 'second getOrCreateSelf() should not re-mark dirty');
  });

  test(
      'listActive() returns non-revoked, non-deleted caregivers sorted by joined_at ASC',
      () async {
    final base = DateTime.utc(2026, 5, 13, 9);

    Future<void> raw({
      required String id,
      required String name,
      required String deviceId,
      required DateTime joinedAt,
      String? revokedAt,
      String? deletedAt,
    }) async {
      await db.insert('caregiver', {
        'id': id,
        'display_name': name,
        'device_id': deviceId,
        'role': 'editor',
        'joined_at': joinedAt.toUtc().toIso8601String(),
        'revoked_at': revokedAt,
        'created_at': joinedAt.toUtc().toIso8601String(),
        'updated_at': joinedAt.toUtc().toIso8601String(),
        'deleted_at': deletedAt,
        'version': 1,
      });
    }

    // Active, joined latest.
    await raw(
      id: 'cg-late',
      name: 'Late',
      deviceId: 'd1',
      joinedAt: base.add(const Duration(hours: 3)),
    );
    // Active, joined earliest.
    await raw(
      id: 'cg-early',
      name: 'Early',
      deviceId: 'd2',
      joinedAt: base,
    );
    // Revoked — must be excluded.
    await raw(
      id: 'cg-revoked',
      name: 'Revoked',
      deviceId: 'd3',
      joinedAt: base.add(const Duration(hours: 1)),
      revokedAt: base.add(const Duration(hours: 2)).toUtc().toIso8601String(),
    );
    // Soft-deleted — must be excluded.
    await raw(
      id: 'cg-deleted',
      name: 'Deleted',
      deviceId: 'd4',
      joinedAt: base.add(const Duration(hours: 2)),
      deletedAt: base.add(const Duration(hours: 4)).toUtc().toIso8601String(),
    );

    final active = await repo().listActive();
    expect(active.length, 2);
    expect(active[0].id, 'cg-early');
    expect(active[1].id, 'cg-late');
  });
}
