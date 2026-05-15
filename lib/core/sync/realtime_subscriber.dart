import 'dart:async';

import 'package:flutter/foundation.dart';

import 'sync_server.dart';

typedef IncomingRowHandler = Future<void> Function(RemoteEncryptedRow row);

/// Coarse health of the realtime websocket as observed by the subscriber.
///
/// * [offline] — not connected. Either pre-`connect()`, post-`disconnect()`,
///   or the reconnect budget has been exhausted.
/// * [connected] — the underlying stream is open and we have either just
///   subscribed or recently received an event without error.
/// * [degraded] — the stream reported an error and a reconnect attempt is
///   in flight (or scheduled).
enum RealtimeStatus { connected, degraded, offline }

/// Subscribes to the family's Realtime stream provided by [SyncServer] and
/// forwards each row to [onIncomingRow]. The underlying stream is
/// already family-filtered + mapped by the server implementation.
///
/// Production wraps a Supabase Realtime channel; tests wrap an in-memory
/// stream. RealtimeSubscriber is concerned with the subscription
/// lifecycle (connect / disconnect), exception isolation in the handler,
/// and reconnect-with-backoff on websocket error.
///
/// The reconnect state machine:
///   * `connect()` opens the stream → status [RealtimeStatus.connected].
///   * On stream error → status [RealtimeStatus.degraded], a reconnect is
///     scheduled with exponential backoff (1s, 2s, 4s, 8s, 16s, 30s, 30s…).
///   * After [_maxReconnectAttempts] consecutive failures → status
///     [RealtimeStatus.offline] and no further attempts are made until the
///     caller invokes `connect()` again.
///   * If a connection stays up for at least [_stableConnectionWindow], the
///     attempt counter is reset so a future momentary drop starts the
///     backoff schedule from scratch.
///   * `disconnect()` cancels any pending reconnect and returns to offline.
class RealtimeSubscriber {
  RealtimeSubscriber({
    required this.server,
    required this.onIncomingRow,
    this.onError,
    Duration? stableConnectionWindow,
    Duration Function(int attempt)? backoffStrategy,
  })  : _stableConnectionWindow =
            stableConnectionWindow ?? const Duration(seconds: 30),
        _backoffStrategy = backoffStrategy ?? _reconnectDelay;

  final SyncServer server;
  final IncomingRowHandler onIncomingRow;
  final void Function(Object error)? onError;

  /// How long a connection must stay healthy before the attempt counter is
  /// reset to 0. Overridable for tests; defaults to 30 seconds.
  final Duration _stableConnectionWindow;

  /// Maps a 1-indexed attempt number to its reconnect delay. Production
  /// uses [_reconnectDelay]; tests pass `(_) => Duration.zero` to flatten
  /// the schedule without resorting to a fake clock.
  final Duration Function(int attempt) _backoffStrategy;

  static const int _maxReconnectAttempts = 10;

  StreamSubscription<RemoteEncryptedRow>? _sub;
  RealtimeStatus _status = RealtimeStatus.offline;
  final StreamController<RealtimeStatus> _statusController =
      StreamController<RealtimeStatus>.broadcast();

  String? _familyId;
  int _attempt = 0;
  Timer? _reconnectTimer;
  Timer? _stableTimer;
  bool _disposed = false;
  // Monotonic generation counter — every (re)connect bumps it so that a
  // late callback from a stale subscription can be ignored.
  int _generation = 0;

  /// The most recent status emitted by the state machine.
  RealtimeStatus get status => _status;

  /// Broadcast stream of status transitions. Subscribers receive subsequent
  /// transitions only; the current value is exposed via [status].
  Stream<RealtimeStatus> get statusStream => _statusController.stream;

  /// Number of consecutive failed reconnect attempts since the last stable
  /// connection. Zero while healthy. Exposed for tests + status surfaces.
  int get reconnectAttempt => _attempt;

  /// True when there is a live (non-cancelled) subscription. Kept for
  /// backwards compatibility with existing callers that pre-date the state
  /// machine; prefer [status] for new code.
  bool get isConnected => _sub != null;

  /// Opens a subscription for [familyId]. Cancels any prior subscription
  /// first. Safe to call repeatedly; each call resets the reconnect budget.
  Future<void> connect({required String familyId}) async {
    if (_disposed) return;
    await _teardown();
    _familyId = familyId;
    _attempt = 0;
    _openSubscription();
  }

  /// Cancels the current subscription and any pending reconnect, returning
  /// the subscriber to [RealtimeStatus.offline]. Idempotent.
  Future<void> disconnect() async {
    _familyId = null;
    await _teardown();
    _setStatus(RealtimeStatus.offline);
  }

  /// Permanently disposes the subscriber. Releases the status controller so
  /// listeners can free their stream subscriptions. After dispose, all
  /// connect/disconnect calls are no-ops.
  Future<void> dispose() async {
    _disposed = true;
    await _teardown();
    await _statusController.close();
  }

  // ── internal ──────────────────────────────────────────────────────────────

  void _openSubscription() {
    final familyId = _familyId;
    if (familyId == null || _disposed) return;
    _generation += 1;
    final generation = _generation;
    _sub = server.realtimeStream(familyId: familyId).listen(
      (row) => _handleRow(row, generation),
      onError: (Object error) => _handleError(error, generation),
      onDone: () => _handleDone(generation),
    );
    _setStatus(RealtimeStatus.connected);
    _scheduleStableReset();
  }

  Future<void> _handleRow(RemoteEncryptedRow row, int generation) async {
    if (generation != _generation) return; // stale callback
    try {
      await onIncomingRow(row);
    } catch (e) {
      // Swallow — handler errors should not kill the subscription.
      // SyncWorker._applyIncoming already discards bad rows silently, but
      // unexpected throws (DB lock, missing key, deserialise crash) deserve a
      // debug-only log so they're not invisible.
      if (kDebugMode) {
        debugPrint('[realtime-drop] table=${row.tableName} '
            'id=${row.recordId} ver=${row.version} err=$e');
      }
    }
  }

  void _handleError(Object error, int generation) {
    if (generation != _generation || _disposed) return;
    onError?.call(error);
    _stableTimer?.cancel();
    _stableTimer = null;
    // Cancel the dying subscription synchronously so a later onDone for
    // the same generation does not race the reconnect schedule.
    final dying = _sub;
    _sub = null;
    dying?.cancel();
    _scheduleReconnect();
  }

  void _handleDone(int generation) {
    if (generation != _generation || _disposed) return;
    if (_status == RealtimeStatus.connected) {
      // The server closed the stream without an explicit error — route
      // through the same recovery path the Supabase implementation uses
      // when the websocket drops.
      _handleError(const _RealtimeStreamClosed(), generation);
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (_attempt >= _maxReconnectAttempts) {
      _setStatus(RealtimeStatus.offline);
      return;
    }
    _attempt += 1;
    _setStatus(RealtimeStatus.degraded);
    final delay = _backoffStrategy(_attempt);
    final generation = _generation;
    _reconnectTimer = Timer(delay, () {
      if (_disposed || _familyId == null) return;
      if (generation != _generation) return;
      _openSubscription();
    });
  }

  void _scheduleStableReset() {
    _stableTimer?.cancel();
    final generation = _generation;
    _stableTimer = Timer(_stableConnectionWindow, () {
      if (_disposed) return;
      if (generation != _generation) return;
      // Connection has held steady — clear the failure budget so a future
      // momentary drop doesn't immediately exhaust attempts.
      _attempt = 0;
    });
  }

  void _setStatus(RealtimeStatus next) {
    if (_status == next) return;
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }

  Future<void> _teardown() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stableTimer?.cancel();
    _stableTimer = null;
    final sub = _sub;
    _sub = null;
    _generation += 1; // invalidate any in-flight callbacks
    if (sub != null) {
      await sub.cancel();
    }
  }

  /// Exponential backoff schedule: 1s, 2s, 4s, 8s, 16s, 30s, 30s, … capped
  /// at 30s. `attempt` is 1-indexed; attempt 0 returns zero delay.
  /// Exposed via [reconnectDelay] for tests. Visible for testing — do not
  /// invoke from production code; use the schedule managed by [connect].
  static Duration reconnectDelay(int attempt) => _reconnectDelay(attempt);

  static Duration _reconnectDelay(int attempt) {
    if (attempt < 1) return Duration.zero;
    final base = attempt > 5 ? 30 : (1 << (attempt - 1));
    return Duration(seconds: base.clamp(1, 30));
  }
}

/// Internal marker error used when the underlying stream completes without
/// an explicit error. Lets [RealtimeSubscriber] route both `onError` and
/// `onDone` through the same recovery path.
class _RealtimeStreamClosed implements Exception {
  const _RealtimeStreamClosed();
  @override
  String toString() => 'RealtimeStreamClosed';
}
