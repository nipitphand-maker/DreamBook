import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/db/migrations/m001_initial.dart';
import 'package:dreambook/core/db/migrations/m002_v2.dart';
import 'package:dreambook/core/db/migrations/m003_v3.dart';
import 'package:dreambook/core/db/migrations/m004_v4.dart';
import 'package:dreambook/core/db/migrations/m005_daily_note.dart';
import 'package:dreambook/core/db/migrations/m006_sync_written_by.dart';
import 'package:dreambook/core/db/migrations/m007_sync_cursors.dart';
import 'package:dreambook/core/db/migrations/migrations.dart';
import 'package:dreambook/features/summary/data/summary_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Returns the local-day ISO date string (YYYY-MM-DD) for [d].
///
/// This mirrors what `date(ts, 'localtime')` returns from SQLite — we use
/// it so the assertions match whatever timezone the test host happens to
/// be running in (CI machines vary; the test must remain green either way).
String _localDateOf(DateTime utc) {
  final l = utc.toLocal();
  return '${l.year.toString().padLeft(4, '0')}-'
      '${l.month.toString().padLeft(2, '0')}-'
      '${l.day.toString().padLeft(2, '0')}';
}

void main() {
  setUpAll(() => sqfliteFfiInit());

  late Database db;
  late ProviderContainer container;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
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
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((_) async => db),
      ],
    );

    await db.insert('baby', {
      'id': 'b1',
      'name': 'Mali',
      'dob': '2026-03-01',
      'preferred_unit': 'oz',
      'created_at': '2026-05-13T00:00:00.000Z',
      'updated_at': '2026-05-13T00:00:00.000Z',
      'version': 1,
    });
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  // We anchor the test data inside a single calendar month so the test is
  // independent of which timezone CI runs in. May 10/15/20 noon UTC are
  // safely "May 10 / 15 / 20 local" in every IANA zone (UTC-12..UTC+14).
  final feedDay = DateTime.utc(2026, 5, 10, 12);
  final diaperDay = DateTime.utc(2026, 5, 15, 12);
  final pumpDay = DateTime.utc(2026, 5, 20, 12);

  test(
    'summaryActivityDaysProvider returns the local dates of all logged rows',
    () async {
      // Feed row on May 10
      await db.insert('feed', {
        'id': 'f1',
        'baby_id': 'b1',
        'type': 'breast',
        'side': 'left',
        'started_at': feedDay.toIso8601String(),
        'created_at': feedDay.toIso8601String(),
        'updated_at': feedDay.toIso8601String(),
        'version': 1,
      });

      // Diaper row on May 15
      await db.insert('diaper', {
        'id': 'd1',
        'baby_id': 'b1',
        'type': 'pee',
        'occurred_at': diaperDay.toIso8601String(),
        'created_at': diaperDay.toIso8601String(),
        'updated_at': diaperDay.toIso8601String(),
        'version': 1,
      });

      // Pump row on May 20
      await db.insert('pump_session', {
        'id': 'p1',
        'baby_id': 'b1',
        'left_oz': 2.0,
        'right_oz': 2.0,
        'started_at': pumpDay.toIso8601String(),
        'created_at': pumpDay.toIso8601String(),
        'updated_at': pumpDay.toIso8601String(),
        'version': 1,
      });

      final days = await container
          .read(summaryActivityDaysProvider(('b1', 2026, 5)).future);

      expect(
        days,
        equals(<String>{
          _localDateOf(feedDay),
          _localDateOf(diaperDay),
          _localDateOf(pumpDay),
        }),
      );
    },
  );

  test('summaryActivityDaysProvider excludes soft-deleted rows', () async {
    final live = DateTime.utc(2026, 5, 8, 12);
    final deleted = DateTime.utc(2026, 5, 22, 12);

    await db.insert('feed', {
      'id': 'fLive',
      'baby_id': 'b1',
      'type': 'breast',
      'started_at': live.toIso8601String(),
      'created_at': live.toIso8601String(),
      'updated_at': live.toIso8601String(),
      'version': 1,
    });
    await db.insert('feed', {
      'id': 'fGone',
      'baby_id': 'b1',
      'type': 'breast',
      'started_at': deleted.toIso8601String(),
      'created_at': deleted.toIso8601String(),
      'updated_at': deleted.toIso8601String(),
      'deleted_at': deleted.toIso8601String(),
      'version': 2,
    });

    final days = await container
        .read(summaryActivityDaysProvider(('b1', 2026, 5)).future);

    expect(days, contains(_localDateOf(live)));
    expect(days, isNot(contains(_localDateOf(deleted))));
  });

  test(
    'summaryActivityDaysProvider returns empty set for a month with no rows',
    () async {
      final days = await container
          .read(summaryActivityDaysProvider(('b1', 2025, 1)).future);
      expect(days, isEmpty);
    },
  );

  test('summaryActivityDaysProvider scopes by babyId', () async {
    // Insert a second baby + a feed for it on May 12.
    await db.insert('baby', {
      'id': 'b2',
      'name': 'Other',
      'dob': '2026-03-01',
      'preferred_unit': 'oz',
      'created_at': '2026-05-13T00:00:00.000Z',
      'updated_at': '2026-05-13T00:00:00.000Z',
      'version': 1,
    });
    final other = DateTime.utc(2026, 5, 12, 12);
    await db.insert('feed', {
      'id': 'fOther',
      'baby_id': 'b2',
      'type': 'breast',
      'started_at': other.toIso8601String(),
      'created_at': other.toIso8601String(),
      'updated_at': other.toIso8601String(),
      'version': 1,
    });

    final daysB1 = await container
        .read(summaryActivityDaysProvider(('b1', 2026, 5)).future);
    final daysB2 = await container
        .read(summaryActivityDaysProvider(('b2', 2026, 5)).future);

    expect(daysB1, isEmpty);
    expect(daysB2, equals(<String>{_localDateOf(other)}));
  });
}
