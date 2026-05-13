// lib/core/db/migrations/migrations.dart
import 'package:sqflite_sqlcipher/sqflite.dart';

/// A migration is "I move the DB from version `from` to version `from + 1`".
typedef MigrationStep = Future<void> Function(Database db);

/// Ordered list of migrations. Index 0 = v0 → v1, index 1 = v1 → v2, etc.
/// Append to this list when adding a new schema version. Never reorder,
/// never delete — schema migrations are append-only history.
class Migrations {
  Migrations(this._steps);

  final List<MigrationStep> _steps;

  int get currentVersion => _steps.length;

  Future<void> runAll(Database db) async {
    for (final step in _steps) {
      await step(db);
    }
  }

  Future<void> runFrom(Database db, int oldVersion, int newVersion) async {
    for (var v = oldVersion; v < newVersion; v++) {
      await _steps[v](db);
    }
  }
}
