import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../crypto/crypto_envelope.dart';
import '../crypto/family_key_service.dart';
import 'encrypted_row.dart';
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
  });

  final Database db;
  final SyncServer server;
  final FamilyKeyService familyKeys;
  final CryptoEnvelope envelope;
  final String familyId;
  final String deviceFp;

  DateTime? _lastPullAt;

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

      // SyncServer.insertEncryptedRow translates transport errors into
      // SyncNetworkError / SyncRlsReject — no catch needed here.
      await server.insertEncryptedRow(
        id: const Uuid().v4(),
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
      );

      await db.update(
        'sync_state',
        {
          'dirty': 0,
          'last_synced_at': DateTime.now().toUtc().toIso8601String(),
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
    final rows = await server.pullRows(familyId: familyId, since: _lastPullAt);
    for (final row in rows) {
      await _applyIncoming(row);
    }
    if (rows.isNotEmpty) {
      _lastPullAt = rows
          .map((r) => r.updatedAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
    }
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
