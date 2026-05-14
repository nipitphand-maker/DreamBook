import 'dart:async';

import 'sync_server.dart';

typedef IncomingRowHandler = Future<void> Function(RemoteEncryptedRow row);

/// Subscribes to the family's Realtime stream provided by [SyncServer] and
/// forwards each row to [onIncomingRow]. The underlying stream is
/// already family-filtered + mapped by the server implementation.
///
/// Production wraps a Supabase Realtime channel; tests wrap an in-memory
/// stream. RealtimeSubscriber is concerned only with the subscription
/// lifecycle (connect / disconnect) and exception isolation in the handler.
class RealtimeSubscriber {
  RealtimeSubscriber({
    required this.server,
    required this.onIncomingRow,
    this.onError,
  });

  final SyncServer server;
  final IncomingRowHandler onIncomingRow;
  final void Function(Object error)? onError;

  StreamSubscription<RemoteEncryptedRow>? _sub;

  Future<void> connect({required String familyId}) async {
    await disconnect();
    _sub = server.realtimeStream(familyId: familyId).listen(
      (row) async {
        try {
          await onIncomingRow(row);
        } catch (_) {
          // Swallow — handler errors should not kill the subscription.
          // SyncWorker._applyIncoming already discards bad rows silently.
        }
      },
      onError: (Object error) => onError?.call(error),
    );
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;
  }

  bool get isConnected => _sub != null;
}
