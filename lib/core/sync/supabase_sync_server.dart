import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_server.dart';

/// Production implementation of [SyncServer] backed by the real Supabase client.
///
/// Translates wire-level Supabase responses into the transport-neutral
/// [RemoteEncryptedRow] / [KeyDistributionEnvelope] shapes that [SyncWorker]
/// consumes. Tests use `FakeSupabaseServer` instead — this adapter is never
/// instantiated in unit tests.
class SupabaseSyncServer implements SyncServer {
  SupabaseSyncServer(this._client);

  final SupabaseClient _client;

  @override
  Future<void> insertEncryptedRow({
    required String id,
    required String familyId,
    required String tableName,
    required String recordId,
    required int version,
    required int keyVersion,
    required Uint8List ciphertext,
    required Uint8List aadHash,
    required String writtenByDevice,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) async {
    await _client.from('encrypted_rows').insert({
      'id': id,
      'family_id': familyId,
      'table_name': tableName,
      'record_id': recordId,
      'version': version,
      'key_version': keyVersion,
      'ciphertext': ciphertext,
      'aad_hash': aadHash,
      'written_by_device': writtenByDevice,
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    });
  }

  @override
  Future<List<RemoteEncryptedRow>> pullRows({
    required String familyId,
    DateTime? since,
  }) async {
    var query = _client
        .from('encrypted_rows')
        .select()
        .eq('family_id', familyId);
    if (since != null) {
      query = query.gt('updated_at', since.toIso8601String());
    }
    final rows = await query;
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      return RemoteEncryptedRow(
        tableName: m['table_name'] as String,
        recordId: m['record_id'] as String,
        version: m['version'] as int,
        keyVersion: m['key_version'] as int,
        familyId: m['family_id'] as String,
        ciphertext: Uint8List.fromList((m['ciphertext'] as List).cast<int>()),
        aadHash: Uint8List.fromList((m['aad_hash'] as List).cast<int>()),
        writtenByDevice: m['written_by_device'] as String,
        updatedAt: DateTime.parse(m['updated_at'] as String),
        deletedAt: m['deleted_at'] == null
            ? null
            : DateTime.parse(m['deleted_at'] as String),
      );
    }).toList();
  }

  @override
  Stream<RemoteEncryptedRow> realtimeStream({required String familyId}) {
    final controller = StreamController<RemoteEncryptedRow>.broadcast();
    final channel = _client.channel('encrypted_rows:$familyId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'encrypted_rows',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'family_id',
            value: familyId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (row.isEmpty) return;
            controller.add(RemoteEncryptedRow(
              tableName: row['table_name'] as String,
              recordId: row['record_id'] as String,
              version: row['version'] as int,
              keyVersion: row['key_version'] as int,
              familyId: row['family_id'] as String,
              ciphertext:
                  Uint8List.fromList((row['ciphertext'] as List).cast<int>()),
              aadHash:
                  Uint8List.fromList((row['aad_hash'] as List).cast<int>()),
              writtenByDevice: row['written_by_device'] as String,
              updatedAt: DateTime.parse(row['updated_at'] as String),
              deletedAt: row['deleted_at'] == null
                  ? null
                  : DateTime.parse(row['deleted_at'] as String),
            ));
          },
        )
        .subscribe();
    controller.onCancel = () => channel.unsubscribe();
    return controller.stream;
  }

  @override
  Future<List<KeyDistributionEnvelope>> pullKeyDistribution({
    required String recipientDeviceFp,
  }) async {
    final rows = await _client
        .from('key_distribution')
        .select()
        .eq('recipient_device_fp', recipientDeviceFp);
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      return KeyDistributionEnvelope(
        familyId: m['family_id'] as String,
        recipientDeviceFp: m['recipient_device_fp'] as String,
        keyVersion: m['key_version'] as int,
        wrappedKey:
            Uint8List.fromList((m['wrapped_key'] as List).cast<int>()),
      );
    }).toList();
  }
}
