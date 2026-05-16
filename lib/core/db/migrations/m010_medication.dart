import 'package:sqflite_sqlcipher/sqflite.dart';

Future<void> m010Medication(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS medication_dose (
      id TEXT PRIMARY KEY,
      baby_id TEXT NOT NULL REFERENCES baby(id),
      drug_name TEXT NOT NULL,
      dose_amount REAL NOT NULL,
      dose_unit TEXT NOT NULL,
      given_at TEXT NOT NULL,
      next_dose_at TEXT,
      note TEXT,
      version INTEGER NOT NULL DEFAULT 1,
      deleted_at TEXT,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_med_baby_given ON medication_dose(baby_id, given_at DESC)',
  );
}
