import 'package:sqflite_sqlcipher/sqflite.dart';

Future<void> m001Initial(Database db) async {
  await db.execute('''
    CREATE TABLE meta (
      key        TEXT PRIMARY KEY NOT NULL,
      value      TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');

  await db.execute('''
    CREATE TABLE baby (
      id              TEXT PRIMARY KEY NOT NULL,
      name            TEXT NOT NULL,
      nickname        TEXT,
      dob             TEXT NOT NULL,
      sex             TEXT CHECK (sex IN ('male','female','unspecified')),
      photo_path      TEXT,
      preferred_unit  TEXT NOT NULL DEFAULT 'oz' CHECK (preferred_unit IN ('oz','ml')),
      created_at      TEXT NOT NULL,
      updated_at      TEXT NOT NULL,
      deleted_at      TEXT,
      version         INTEGER NOT NULL DEFAULT 1
    )
  ''');
  await db.execute('CREATE INDEX idx_baby_deleted_at ON baby(deleted_at)');

  await db.execute('''
    CREATE TABLE caregiver (
      id           TEXT PRIMARY KEY NOT NULL,
      display_name TEXT NOT NULL,
      device_id    TEXT NOT NULL,
      role         TEXT NOT NULL DEFAULT 'editor'
                     CHECK (role IN ('read_only','editor','admin')),
      joined_at    TEXT NOT NULL,
      revoked_at   TEXT,
      created_at   TEXT NOT NULL,
      updated_at   TEXT NOT NULL,
      deleted_at   TEXT,
      version      INTEGER NOT NULL DEFAULT 1
    )
  ''');
  await db.execute('CREATE INDEX idx_caregiver_revoked_at ON caregiver(revoked_at)');
  await db.execute('CREATE INDEX idx_caregiver_device_id  ON caregiver(device_id)');

  await db.execute('''
    CREATE TABLE pump_session (
      id           TEXT PRIMARY KEY NOT NULL,
      baby_id      TEXT NOT NULL REFERENCES baby(id) ON DELETE CASCADE,
      left_oz      REAL NOT NULL DEFAULT 0,
      right_oz     REAL NOT NULL DEFAULT 0,
      total_oz     REAL GENERATED ALWAYS AS (left_oz + right_oz) VIRTUAL,
      duration_min INTEGER,
      started_at   TEXT NOT NULL,
      ended_at     TEXT,
      note         TEXT,
      logged_by    TEXT REFERENCES caregiver(id),
      created_at   TEXT NOT NULL,
      updated_at   TEXT NOT NULL,
      deleted_at   TEXT,
      version      INTEGER NOT NULL DEFAULT 1
    )
  ''');
  await db.execute('CREATE INDEX idx_pump_session_baby_started ON pump_session(baby_id, started_at DESC)');

  await db.execute('''
    CREATE TABLE stash_bottle (
      id               TEXT PRIMARY KEY NOT NULL,
      baby_id          TEXT NOT NULL REFERENCES baby(id) ON DELETE CASCADE,
      pump_session_id  TEXT REFERENCES pump_session(id) ON DELETE SET NULL,
      oz               REAL NOT NULL,
      pumped_at        TEXT NOT NULL,
      frozen_at        TEXT,
      expires_at       TEXT NOT NULL,
      storage          TEXT NOT NULL DEFAULT 'freezer'
                         CHECK (storage IN ('freezer','fridge','room')),
      consumed_at      TEXT,
      consumed_feed_id TEXT,
      discarded_at     TEXT,
      logged_by        TEXT REFERENCES caregiver(id),
      created_at       TEXT NOT NULL,
      updated_at       TEXT NOT NULL,
      deleted_at       TEXT,
      version          INTEGER NOT NULL DEFAULT 1
    )
  ''');
  await db.execute('CREATE INDEX idx_stash_baby_expires ON stash_bottle(baby_id, expires_at)');
  await db.execute('CREATE INDEX idx_stash_baby_active  ON stash_bottle(baby_id, consumed_at, discarded_at)');
  await db.execute('CREATE INDEX idx_stash_pump_session ON stash_bottle(pump_session_id)');

  await db.execute('''
    CREATE TABLE feed (
      id                   TEXT PRIMARY KEY NOT NULL,
      baby_id              TEXT NOT NULL REFERENCES baby(id) ON DELETE CASCADE,
      type                 TEXT NOT NULL CHECK (type IN ('breast','bottle')),
      side                 TEXT CHECK (side IN ('left','right','both')),
      oz                   REAL,
      source               TEXT CHECK (source IN ('breastmilk','formula')),
      from_stash_bottle_id TEXT REFERENCES stash_bottle(id) ON DELETE SET NULL,
      started_at           TEXT NOT NULL,
      ended_at             TEXT,
      note                 TEXT,
      logged_by            TEXT REFERENCES caregiver(id),
      created_at           TEXT NOT NULL,
      updated_at           TEXT NOT NULL,
      deleted_at           TEXT,
      version              INTEGER NOT NULL DEFAULT 1
    )
  ''');
  await db.execute('CREATE INDEX idx_feed_baby_started ON feed(baby_id, started_at DESC)');
  await db.execute('CREATE INDEX idx_feed_baby_live    ON feed(baby_id, deleted_at, started_at)');
  await db.execute('CREATE INDEX idx_feed_from_stash   ON feed(from_stash_bottle_id)');

  await db.execute('''
    CREATE TABLE diaper (
      id          TEXT PRIMARY KEY NOT NULL,
      baby_id     TEXT NOT NULL REFERENCES baby(id) ON DELETE CASCADE,
      type        TEXT NOT NULL CHECK (type IN ('pee','poop','mixed','dry')),
      color       TEXT,
      consistency TEXT,
      occurred_at TEXT NOT NULL,
      note        TEXT,
      logged_by   TEXT REFERENCES caregiver(id),
      created_at  TEXT NOT NULL,
      updated_at  TEXT NOT NULL,
      deleted_at  TEXT,
      version     INTEGER NOT NULL DEFAULT 1
    )
  ''');
  await db.execute('CREATE INDEX idx_diaper_baby_occurred ON diaper(baby_id, occurred_at DESC)');
  await db.execute('CREATE INDEX idx_diaper_baby_live     ON diaper(baby_id, deleted_at, occurred_at)');

  await db.execute('''
    CREATE TABLE sleep (
      id           TEXT PRIMARY KEY NOT NULL,
      baby_id      TEXT NOT NULL REFERENCES baby(id) ON DELETE CASCADE,
      started_at   TEXT NOT NULL,
      ended_at     TEXT,
      duration_min INTEGER,
      location     TEXT CHECK (location IN ('crib','stroller','car','other')),
      note         TEXT,
      logged_by    TEXT REFERENCES caregiver(id),
      created_at   TEXT NOT NULL,
      updated_at   TEXT NOT NULL,
      deleted_at   TEXT,
      version      INTEGER NOT NULL DEFAULT 1
    )
  ''');
  await db.execute('CREATE INDEX idx_sleep_baby_started ON sleep(baby_id, started_at DESC)');
  await db.execute('CREATE INDEX idx_sleep_baby_live    ON sleep(baby_id, deleted_at, started_at)');

  await db.execute('''
    CREATE TABLE vaccination (
      id           TEXT PRIMARY KEY NOT NULL,
      baby_id      TEXT NOT NULL REFERENCES baby(id) ON DELETE CASCADE,
      vaccine_name TEXT NOT NULL,
      given_on     TEXT NOT NULL,
      clinic       TEXT,
      note         TEXT,
      logged_by    TEXT REFERENCES caregiver(id),
      created_at   TEXT NOT NULL,
      updated_at   TEXT NOT NULL,
      deleted_at   TEXT,
      version      INTEGER NOT NULL DEFAULT 1
    )
  ''');
  await db.execute('CREATE INDEX idx_vaccination_baby_given ON vaccination(baby_id, given_on DESC)');

  await db.execute('''
    CREATE TABLE sync_state (
      record_id       TEXT NOT NULL,
      table_name      TEXT NOT NULL,
      version         INTEGER NOT NULL,
      updated_at      TEXT NOT NULL,
      dirty           INTEGER NOT NULL DEFAULT 1 CHECK (dirty IN (0,1)),
      last_synced_at  TEXT,
      PRIMARY KEY (record_id, table_name)
    )
  ''');
  await db.execute('CREATE INDEX idx_sync_state_dirty ON sync_state(dirty, updated_at)');
  await db.execute('CREATE INDEX idx_sync_state_table ON sync_state(table_name, updated_at)');

  await db.insert('meta', {
    'key': 'schema_version',
    'value': '1',
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  });
}
