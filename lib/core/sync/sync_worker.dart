import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../crypto/crypto_envelope.dart';
import '../crypto/family_key_service.dart';
import 'conflict_resolver.dart';
import 'count_attestation.dart';
import 'encrypted_row.dart';
import 'retry_policy.dart';
import 'sync_error.dart';
import 'sync_server.dart';

/// Tables Plan B logs into. The push loop joins `sync_state.table_name`
/// to one of these to fetch the plaintext row.
const List<String> _syncableTables = [
  'baby',
  'caregiver',
  'pump_session',
  'stash_bottle',
  'feed',
  'diaper',
  'sleep',
  'vaccination',
  'daily_note',
];

/// Push (Task 5) + pull (Task 6) of encrypted rows. Tests inject a
/// [FakeSupabaseServer] (which implements [SyncServer]); production
/// supplies a `SupabaseSyncServer` adapter (Task 15).
///
/// Design note: [SyncServer] implementations are responsible for
/// translating their own transport exceptions into [SyncNetworkError] or
/// [SyncRlsReject] before they propagate here. This keeps [SyncWorker]
/// free of any dependency on test fakes or Supabase internals.
class SyncWorker {
  SyncWorker({
    required this.db,
    required this.server,
    required this.familyKeys,
    required this.envelope,
    required this.familyId,
    required this.deviceFp,
    this.attestation,
  });

  final Database db;
  final SyncServer server;
  final FamilyKeyService familyKeys;
  final CryptoEnvelope envelope;
  final String familyId;
  final String deviceFp;
  final CountAttestation? attestation;

  /// In-memory cache of the persisted cursor in `sync_cursors`. Lazily
  /// loaded on first [pullOnce] so cold-start picks up the cursor written
  /// by a previous app launch (incremental pull).
  DateTime? _lastPullAt;
  bool _cursorLoaded = false;

  /// Visible for tests only — returns the in-memory cursor without
  /// touching the DB. Production code must not depend on this.
  DateTime? get debugLastPullAt => _lastPullAt;

  /// Drains the dirty queue once. Throws [SyncNetworkError] on transport
  /// failure (caller retries) or [SyncRlsReject] on server-side denial
  /// (caller stops worker and surfaces a modal).
  Future<void> pushOnce() async {
    final dirty = await db.query(
      'sync_state',
      where: 'dirty = 1',
      orderBy: 'updated_at ASC',
    );
    if (dirty.isEmpty) return;

    final key = await familyKeys.read(familyId: familyId);
    if (key == null) {
      throw const SyncRlsReject('No K_family in storage for this family');
    }

    for (final entry in dirty) {
      final tableName = entry['table_name'] as String;
      final recordId = entry['record_id'] as String;
      final version = entry['version'] as int;
      if (!_syncableTables.contains(tableName)) continue;

      final rows = await db.query(
        tableName,
        where: 'id = ?',
        whereArgs: [recordId],
      );
      if (rows.isEmpty) continue;
      final plaintext = rows.first;

      final aad = EncryptedRow.aadFor(
        tableName: tableName,
        recordId: recordId,
        version: version,
        familyId: familyId,
        keyVersion: key.keyVersion,
      );
      final ciphertext = await envelope.seal(
        utf8.encode(jsonEncode(plaintext)),
        SecretKey(key.bytes),
        utf8.encode(aad),
      );
      final aadHash = Uint8List.fromList(
        (await Blake2b().hash(utf8.encode(aad))).bytes,
      );

      // Deterministic UUID v5 so retries always produce the same id — the
      // upsert in SupabaseSyncServer can then use the PK as the conflict key.
      final pushId = const Uuid().v5(
        Namespace.url.value,
        '$familyId:$tableName:$recordId:$version',
      );
      // SyncServer.insertEncryptedRow translates transport errors into
      // SyncNetworkError / SyncRlsReject — no catch needed here.
      // RetryPolicy.run wraps transient transport faults (Socket/Timeout/5xx)
      // with exponential backoff; terminal errors (incl. SyncRlsReject and
      // SyncNetworkError, neither of which match transient classification)
      // are rethrown immediately so the caller can react.
      await RetryPolicy.run(
        () => server.insertEncryptedRow(
          id: pushId,
          familyId: familyId,
          tableName: tableName,
          recordId: recordId,
          version: version,
          keyVersion: key.keyVersion,
          ciphertext: ciphertext,
          aadHash: aadHash,
          writtenByDevice: deviceFp,
          updatedAt: DateTime.now().toUtc(),
          deletedAt: (plaintext['deleted_at'] as String?) == null
              ? null
              : DateTime.now().toUtc(),
        ),
      );

      await db.update(
        'sync_state',
        {
          'dirty': 0,
          'last_synced_at': DateTime.now().toUtc().toIso8601String(),
          'written_by_device': deviceFp,
        },
        where: 'record_id = ? AND table_name = ?',
        whereArgs: [recordId, tableName],
      );
    }
  }

  /// Pulls every encrypted row for this family written since the last pull,
  /// decrypts each via [envelope], verifies aad_hash against expected AAD,
  /// then upserts the plaintext into the owning local table. Rows whose
  /// aad_hash doesn't recompute are discarded (silent — tamper).
  /// Rows that fail to decrypt (wrong key) are discarded; the loop
  /// continues to the next row.
  Future<void> pullOnce() async {
    // Hydrate the in-memory cursor from sync_cursors on first call so
    // cold-start does an incremental pull from where the previous app
    // launch left off.
    if (!_cursorLoaded) {
      _lastPullAt = await _readCursor();
      _cursorLoaded = true;
    }
    // RetryPolicy.run wraps transient transport faults (Socket/Timeout/5xx)
    // with exponential backoff; terminal errors are rethrown immediately.
    final rows = await RetryPolicy.run(
      () => server.pullRows(familyId: familyId, since: _lastPullAt),
    );
    for (final row in rows) {
      await _applyIncoming(row);
    }
    if (rows.isNotEmpty) {
      final newCursor = rows
          .map((r) => r.updatedAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      _lastPullAt = newCursor;
      await _writeCursor(newCursor);
    }
    await attestation?.verify();
  }

  /// Reads the persisted `last_pull_at` for [familyId]. Returns `null`
  /// when no cursor exists yet (fresh device or first run after upgrade) —
  /// the next pull will fetch from the beginning of time.
  Future<DateTime?> _readCursor() async {
    final rows = await db.query(
      'sync_cursors',
      columns: ['last_pull_at'],
      where: 'family_id = ?',
      whereArgs: [familyId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['last_pull_at'] as String);
  }

  /// Persists [cursor] as the latest applied server timestamp for
  /// [familyId]. Uses `ConflictAlgorithm.replace` because there is at
  /// most one cursor row per family (PK lookup).
  Future<void> _writeCursor(DateTime cursor) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    await db.insert(
      'sync_cursors',
      {
        'family_id': familyId,
        'last_pull_at': cursor.toIso8601String(),
        'updated_at': nowIso,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Called by RealtimeSubscriber (Task 7) when a row arrives via websocket.
  Future<void> onIncomingRow(RemoteEncryptedRow row) => _applyIncoming(row);

  Future<void> _applyIncoming(RemoteEncryptedRow row) async {
    final key = await familyKeys.read(familyId: familyId);
    if (key == null) return;

    final expectedAad = EncryptedRow.aadFor(
      tableName: row.tableName,
      recordId: row.recordId,
      version: row.version,
      familyId: row.familyId,
      keyVersion: row.keyVersion,
    );
    final expectedHash = Uint8List.fromList(
      (await Blake2b().hash(utf8.encode(expectedAad))).bytes,
    );
    if (!_constantTimeEquals(expectedHash, row.aadHash)) {
      // Tampered metadata — discard silently.
      return;
    }
    Uint8List plaintextBytes;
    try {
      plaintextBytes = await envelope.open(
        Uint8List.fromList(row.ciphertext),
        SecretKey(key.bytes),
        utf8.encode(expectedAad),
      );
    } catch (_) {
      // Wrong key / modified ciphertext — discard, continue loop.
      return;
    }
    final plaintext = jsonDecode(utf8.decode(plaintextBytes)) as Map<String, Object?>;

    // Version guard: skip if we already have this row at the same or higher version.
    // This prevents older versions (e.g. from a slow replica) from overwriting
    // newer local edits. For daily_note we also check by (baby_id, date) to
    // prevent ping-pong when two caregivers create independent notes for the same day.
    final rowId = plaintext['id'] as String?;
    if (rowId != null) {
      final existing = await db.query(
        row.tableName,
        columns: ['version', 'updated_at'],
        where: 'id = ?',
        whereArgs: [rowId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final localVersion = existing.first['version'] as int? ?? 0;
        if (localVersion > row.version) return;
        if (localVersion == row.version) {
          // Same version — use LWW ConflictResolver so all replicas
          // settle on the same winner (updated_at, then device_fp tie-break).
          final syncMeta = await db.query(
            'sync_state',
            columns: ['written_by_device'],
            where: 'record_id = ? AND table_name = ?',
            whereArgs: [rowId, row.tableName],
            limit: 1,
          );
          final localTs = DateTime.tryParse(
                existing.first['updated_at'] as String? ?? '') ??
              DateTime.utc(2000);
          final remoteTs = DateTime.tryParse(
                plaintext['updated_at'] as String? ?? '') ??
              DateTime.utc(2000);
          final localFp = syncMeta.isNotEmpty
              ? (syncMeta.first['written_by_device'] as String? ?? deviceFp)
              : deviceFp;
          final outcome = ConflictResolver.decide(
            ResolverRow(
              version: localVersion,
              updatedAt: localTs,
              writtenByDevice: localFp,
              deleted: false,
            ),
            ResolverRow(
              version: row.version,
              updatedAt: remoteTs,
              writtenByDevice: row.writtenByDevice,
              deleted: row.deletedAt != null,
            ),
          );
          if (outcome == ResolveOutcome.keepLocal) return;
        }
        // localVersion < row.version: fall through to apply
      }
    }

    if (row.tableName == 'daily_note') {
      final babyId = plaintext['baby_id'] as String?;
      final date = plaintext['date'] as String?;
      if (babyId != null && date != null) {
        final byDate = await db.query(
          'daily_note',
          columns: ['updated_at'],
          where: 'baby_id = ? AND date = ?',
          whereArgs: [babyId, date],
          limit: 1,
        );
        if (byDate.isNotEmpty) {
          final existingTs = byDate.first['updated_at'] as String? ?? '';
          final incomingTs = plaintext['updated_at'] as String? ?? '';
          // ISO-8601 strings sort lexicographically — no parse needed.
          if (existingTs.compareTo(incomingTs) >= 0) return;
        }
      }
    }

    // Tombstone branch: a row arriving with deletedAt set is a remote DELETE
    // we must propagate locally. We've already cleared the version + LWW
    // guards above, so applying the delete here is safe and won't clobber a
    // newer local edit. The owning row is removed from its table and the
    // sync_state ledger is updated so we don't try to re-push the deletion.
    if (row.deletedAt != null) {
      await db.transaction((txn) async {
        await txn.delete(
          row.tableName,
          where: 'id = ?',
          whereArgs: [row.recordId],
        );
        await txn.insert(
          'sync_state',
          {
            'record_id': row.recordId,
            'table_name': row.tableName,
            'version': row.version,
            'updated_at': row.updatedAt.toIso8601String(),
            'dirty': 0,
            'last_synced_at': DateTime.now().toUtc().toIso8601String(),
            'written_by_device': row.writtenByDevice,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
      return;
    }

    await db.transaction((txn) async {
      await txn.insert(
        row.tableName,
        plaintext,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'sync_state',
        {
          'record_id': row.recordId,
          'table_name': row.tableName,
          'version': row.version,
          'updated_at': row.updatedAt.toIso8601String(),
          'dirty': 0,
          'last_synced_at': DateTime.now().toUtc().toIso8601String(),
          'written_by_device': row.writtenByDevice,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
