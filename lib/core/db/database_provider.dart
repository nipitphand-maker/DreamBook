import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../services/secure_key_service.dart';
import 'migrations/m001_initial.dart';
import 'migrations/m002_v2.dart';
import 'migrations/m003_v3.dart';
import 'migrations/m004_v4.dart';
import 'migrations/m005_daily_note.dart';
import 'migrations/m006_sync_written_by.dart';
import 'migrations/m007_sync_cursors.dart';
import 'migrations/m008_milestone.dart';
import 'migrations/migrations.dart';

final migrationsProvider = Provider<Migrations>(
  (_) => Migrations([
    m001Initial,
    m002V2,
    m003V3,
    m004V4,
    m005DailyNote,
    m006SyncWrittenBy,
    m007SyncCursors,
    m008Milestone,
  ]),
);

final appDatabaseProvider = FutureProvider<Database>((ref) async {
  final key = await SecureKeyService.getOrCreateDbKey();
  final dir = await getDatabasesPath();
  final path = p.join(dir, 'dreambook.db');
  final migrations = ref.watch(migrationsProvider);

  return openDatabase(
    path,
    password: key,
    version: migrations.currentVersion,
    onConfigure: (db) async {
      // foreign_keys must be set before any DML — safe in onConfigure.
      await db.execute('PRAGMA foreign_keys = ON');
    },
    onCreate: (db, _) => migrations.runAll(db),
    onUpgrade: (db, oldV, newV) => migrations.runFrom(db, oldV, newV),
    onOpen: (db) async {
      // sqflite v2+ restricts open callbacks to rawQuery — execute is blocked.
      await db.rawQuery('PRAGMA journal_mode = WAL');
      await db.rawQuery('PRAGMA secure_delete = ON');
      await db.rawQuery('PRAGMA synchronous = NORMAL');
    },
  );
});
