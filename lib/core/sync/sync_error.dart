/// Network error during sync — caller retries with backoff.
class SyncNetworkError implements Exception {
  const SyncNetworkError(this.cause);
  final Object cause;
  @override
  String toString() => 'SyncNetworkError: $cause';
}

/// Server rejected this device. Either revoked or `key_version` stale.
class SyncRlsReject implements Exception {
  const SyncRlsReject(this.message);
  final String message;
  @override
  String toString() => 'SyncRlsReject: $message';
}

/// AAD or MAC mismatch on a pulled row. Discard and log.
class SyncDecryptFailure implements Exception {
  const SyncDecryptFailure(this.message);
  final String message;
  @override
  String toString() => 'SyncDecryptFailure: $message';
}

/// Incoming row has aad_hash that doesn't match the recomputed AAD.
class SyncEnvelopeTamper implements Exception {
  const SyncEnvelopeTamper(this.message);
  final String message;
  @override
  String toString() => 'SyncEnvelopeTamper: $message';
}
