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
}
