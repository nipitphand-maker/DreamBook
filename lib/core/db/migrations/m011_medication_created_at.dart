import 'package:sqflite_sqlcipher/sqflite.dart';

Future<void> m011MedicationCreatedAt(Database db) async {
  // Wrap in a transaction so both statements succeed or fail together.
  // SQLite supports transactional DDL (ALTER TABLE is rollback-able),
  // preventing a crash between the two statements from leaving rows with
  // created_at = '' permanently.
  await db.transaction((txn) async {
    await txn.execute(
      "ALTER TABLE medication_dose ADD COLUMN created_at TEXT NOT NULL DEFAULT ''",
    );
    await txn.execute(
      "UPDATE medication_dose SET created_at = updated_at WHERE created_at = ''",
    );
  });
}
