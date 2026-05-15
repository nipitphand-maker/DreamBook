import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'bytea_codec.dart';
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

  /// Diagnostic — used by SyncWorker to log auth state alongside each push
  /// attempt so we can correlate 42501 RLS rejections with the JWT actually
  /// in-flight (vs the one bootstrap_family used).
  Map<String, dynamic>? probeSession() {
    final s = _client.auth.currentSession;
    if (s == null) return {'uid': null, 'hasJwt': false};
    final parts = s.accessToken.split('.');
    String? role;
    int? exp;
    if (parts.length == 3) {
      try {
        final pad = '=' * ((4 - parts[1].length % 4) % 4);
        final payload = utf8.decode(
            base64Url.decode(parts[1].replaceAll('-', '+').replaceAll('_', '/') + pad));
        final map = jsonDecode(payload) as Map<String, dynamic>;
        role = map['role'] as String?;
        exp = map['exp'] as int?;
      } catch (_) {}
    }
    return {
      'uid': s.user.id,
      'hasJwt': true,
      'role': role,
      'exp': exp,
    };
  }

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
    // Upsert on the unique constraint (family_id, table_name, record_id, version)
    // so retries after a network error are idempotent (the id is deterministic).
    await _client.from('encrypted_rows').upsert(
      {
        'id': id,
        'family_id': familyId,
        'table_name': tableName,
        'record_id': recordId,
        'version': version,
        'key_version': keyVersion,
        'ciphertext': ciphertext,
        'aad_hash': aadHash,
        'written_by_device': writtenByDevice, // text column (migration 0014)
        'updated_at': updatedAt.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
      },
      onConflict: 'family_id,table_name,record_id,version',
    );
  }

  // PostgREST default cap is 1000 rows. Fetch in pages to avoid silent truncation.
  static const int _pageSize = 500;

  @override
  Future<List<RemoteEncryptedRow>> pullRows({
    required String familyId,
    DateTime? since,
  }) async {
    final allRows = <Map<String, dynamic>>[];
    int offset = 0;
    while (true) {
      // Filters (.eq, .gt) must come before transforms (.order, .range).
      var filteredQuery = _client
          .from('encrypted_rows')
          .select()
          .eq('family_id', familyId);
      if (since != null) {
        filteredQuery = filteredQuery.gt('updated_at', since.toIso8601String());
      }
      final page = await filteredQuery
          .order('updated_at')
          .range(offset, offset + _pageSize - 1);
      final pageList = (page as List).cast<Map<String, dynamic>>();
      allRows.addAll(pageList);
      if (pageList.length < _pageSize) break;
      offset += _pageSize;
    }
    return allRows.map((m) {
      return RemoteEncryptedRow(
        tableName: m['table_name'] as String,
        recordId: m['record_id'] as String,
        version: m['version'] as int,
        keyVersion: m['key_version'] as int,
        familyId: m['family_id'] as String,
        ciphertext: decodeBytea(m['ciphertext']),
        aadHash: decodeBytea(m['aad_hash']),
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
              ciphertext: decodeBytea(row['ciphertext']),
              aadHash: decodeBytea(row['aad_hash']),
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
        wrappedKey: decodeBytea(m['wrapped_key']),
      );
    }).toList();
  }

  @override
  Future<RevokeResult> revokeCaregiver({
    required String callerDeviceFp,
    required String targetDeviceFp,
  }) async {
    // functions.invoke() throws FunctionException on non-2xx — no status check needed.
    final response = await _client.functions.invoke(
      'revoke_caregiver',
      body: {'target_device_fp': targetDeviceFp},
    );
    final body = response.data as Map<String, dynamic>;
    final survivors = (body['survivors'] as List).map((s) {
      final m = s as Map<String, dynamic>;
      return SurvivorDevice(
        deviceFp: m['device_fp'] as String,
        devicePubKey: base64Decode(m['device_pub_key'] as String),
      );
    }).toList();
    return RevokeResult(
      newKeyVersion: body['new_key_version'] as int,
      survivors: survivors,
    );
  }

  @override
  Future<void> insertKeyDistribution({
    required String familyId,
    required String recipientDeviceFp,
    required int keyVersion,
    required Uint8List wrappedKey,
  }) async {
    await _client.from('key_distribution').insert({
      'family_id': familyId,
      'recipient_device_fp': recipientDeviceFp,
      'key_version': keyVersion,
      'wrapped_key': wrappedKey,
    });
  }

  @override
  Future<Map<String, int>> countRows({required String familyId}) async {
    final response = await _client
        .from('encrypted_rows')
        .select('table_name')
        .eq('family_id', familyId)
        .filter('deleted_at', 'is', null);

    final rows = response as List<dynamic>;
    final counts = <String, int>{};
    for (final row in rows) {
      final tableName = row['table_name'] as String;
      counts[tableName] = (counts[tableName] ?? 0) + 1;
    }
    return counts;
  }

}
