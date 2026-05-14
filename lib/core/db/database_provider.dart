import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../services/secure_key_service.dart';
import 'migrations/m001_initial.dart';
import 'migrations/m002_v2.dart';
import 'migrations/m003_v3.dart';
import 'migrations/migrations.dart';

final migrationsProvider = Provider<Migrations>(
  (_) => Migrations([m001Initial, m002V2, m003V3]),
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
      await db.execute('PRAGMA foreign_keys = ON');
      await db.execute('PRAGMA journal_mode = WAL');
      await db.execute('PRAGMA secure_delete = ON');
      await db.execute('PRAGMA synchronous = NORMAL');
    },
    onCreate: (db, _) => migrations.runAll(db),
    onUpgrade: (db, oldV, newV) => migrations.runFrom(db, oldV, newV),
  );
});
