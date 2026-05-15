import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/sync/sync_lifecycle_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

class DailyNoteRepository {
  DailyNoteRepository(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  Future<Database> get _db => _ref.read(appDatabaseProvider.future);

  /// Returns the note for [babyId] on [date] ("YYYY-MM-DD"), or null.
  Future<DailyNote?> getForDate(String babyId, String date) async {
    final db = await _db;
    final rows = await db.query(
      'daily_note',
      where: 'baby_id = ? AND date = ? AND deleted_at IS NULL',
      whereArgs: [babyId, date],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DailyNote.fromRow(rows.first);
  }

  /// Insert or update the note body for [babyId] on [date].
  /// Marks sync_state dirty so the push loop picks it up.
  Future<DailyNote> upsert({
    required String babyId,
    required String date,
    required String body,
    required String familyId,
    required int keyVersion,
  }) async {
    final db = await _db;
    final now = DateTime.now().toUtc();
    final nowIso = now.toIso8601String();

    final existing = await getForDate(babyId, date);
    final DailyNote note;

    if (existing != null) {
      final nextVersion = existing.version + 1;
      await db.transaction((txn) async {
        await txn.rawUpdate(
          'UPDATE daily_note SET body=?, updated_at=?, version=? WHERE id=?',
          [body, nowIso, nextVersion, existing.id],
        );
        await txn.insert(
          'sync_state',
          {
            'record_id': existing.id,
            'table_name': 'daily_note',
            'version': nextVersion,
            'updated_at': nowIso,
            'dirty': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
      note = DailyNote(
        id: existing.id,
        babyId: babyId,
        date: date,
        body: body,
        familyId: familyId,
        keyVersion: keyVersion,
        createdAt: existing.createdAt,
        updatedAt: now,
        version: nextVersion,
      );
    } else {
      final id = _uuid.v4();
      final newNote = DailyNote(
        id: id,
        babyId: babyId,
        date: date,
        body: body,
        familyId: familyId,
        keyVersion: keyVersion,
        createdAt: now,
        updatedAt: now,
      );
      await db.transaction((txn) async {
        await txn.insert('daily_note', newNote.toRow());
        await txn.insert(
          'sync_state',
          {
            'record_id': id,
            'table_name': 'daily_note',
            'version': 1,
            'updated_at': nowIso,
            'dirty': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
      note = newNote;
    }

    _ref.read(syncLifecycleControllerProvider).schedulePush();
    return note;
  }
}

final dailyNoteRepositoryProvider =
    Provider<DailyNoteRepository>(DailyNoteRepository.new);

final dailyNoteForDateProvider =
    FutureProvider.family<DailyNote?, (String, String)>((ref, params) async {
  final (babyId, date) = params;
  ref.watch(appDatabaseProvider);
  return ref.read(dailyNoteRepositoryProvider).getForDate(babyId, date);
});
