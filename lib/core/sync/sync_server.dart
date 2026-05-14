import 'dart:typed_data';

/// Wire-level representation of a key_distribution row addressed to one device.
class KeyDistributionEnvelope {
  const KeyDistributionEnvelope({
    required this.familyId,
    required this.recipientDeviceFp,
    required this.keyVersion,
    required this.wrappedKey,
  });
  final String familyId;
  final String recipientDeviceFp;
  final int keyVersion;
  final Uint8List wrappedKey;
}

/// Wire-level representation of an encrypted_rows row when it comes back
/// from the server. Plaintext is recovered separately by [SyncWorker].
class RemoteEncryptedRow {
  const RemoteEncryptedRow({
    required this.tableName,
    required this.recordId,
    required this.version,
    required this.keyVersion,
    required this.familyId,
    required this.ciphertext,
    required this.aadHash,
    required this.writtenByDevice,
    required this.updatedAt,
    this.deletedAt,
  });

  final String tableName;
  final String recordId;
  final int version;
  final int keyVersion;
  final String familyId;
  final Uint8List ciphertext;
  final Uint8List aadHash;
  final String writtenByDevice;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

/// Abstract Supabase-shape interface. Production is implemented by
/// `SupabaseSyncServer` (Task 15). Tests implement via `FakeSupabaseServer`.
abstract class SyncServer {
  /// Push one encrypted row. Throws on any failure (caller distinguishes
  /// network vs RLS via exception type from `sync_error.dart`).
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
  });

  /// Pull rows updated after [since]. Order is not guaranteed.
  Future<List<RemoteEncryptedRow>> pullRows({
    required String familyId,
    DateTime? since,
  });

  /// Stream of rows for [familyId] arriving via Realtime. Production
  /// implementation wraps a Supabase channel; tests wrap an in-memory stream.
  Stream<RemoteEncryptedRow> realtimeStream({required String familyId});

  /// Returns the wrapped-key envelopes addressed to this device. Used after
  /// a key rotation to receive the new K_family from the admin.
  Future<List<KeyDistributionEnvelope>> pullKeyDistribution({
    required String recipientDeviceFp,
  });
}
