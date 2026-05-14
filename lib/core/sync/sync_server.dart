import 'dart:typed_data';

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
}
