/// Categorizes a sync error for downstream reporting.
///
/// - [transient]: retry-eligible (network blip, 5xx, rate-limited).
/// - [terminal]: non-retryable (auth refused, schema mismatch, decrypt fail).
/// - [unknown]: not classified — Phase 2 audit log will treat as worst-case.
enum SyncErrorCategory { transient, terminal, unknown }

/// One captured error event. Held in [SyncErrorReporter]'s in-memory buffer
/// for later audit_events upload. Phase 2 (EF audit hooks + DV-6 Sentry) will
/// wire the actual upload — for Phase 1 the reporter exists to PROVE we no
/// longer silently swallow exceptions in the sync lifecycle.
class SyncErrorEvent {
  SyncErrorEvent({
    required this.timestamp,
    required this.category,
    required this.errorType,
    required this.message,
    required this.stackHash,
  });

  /// UTC timestamp captured at [SyncErrorReporter.report] time.
  final DateTime timestamp;

  /// Bucket: transient / terminal / unknown.
  final SyncErrorCategory category;

  /// `error.runtimeType.toString()` — used by the audit log to group repeats
  /// without leaking the full message.
  final String errorType;

  /// `error.toString()`, truncated to 256 chars (ends with `...` if cut).
  /// Truncation guards against pathological huge errors (e.g. server dump).
  final String message;

  /// First 16 hex chars of a 64-bit FNV-1a hash of the stack trace string.
  /// Lets the audit log dedupe repeated crashes without uploading the trace
  /// (which can contain file paths or PII fragments).
  final String stackHash;
}

/// Non-silent error path for sync. Replaces the bare `debugPrint`-only catch
/// in [SyncLifecycleController]. Captures structured metadata about every
/// sync failure so:
///
/// 1. Phase 2 EF audit hooks can upload `audit_events` rows for retro
///    analysis (see plan DV-6).
/// 2. Phase 2 Sentry init can be wired through [onError] — Phase 1 leaves
///    the callback unhooked.
/// 3. The UI flow is untouched — [SyncStatusNotifier.failSync] is still
///    called by the caller, so the user-visible failure state is preserved.
///
/// Deliberately dependency-free. No `package:sentry_flutter`, no `crypto`
/// — we use a tiny FNV-1a hash so this file stays cheap to import.
class SyncErrorReporter {
  SyncErrorReporter({this.onError});

  /// Optional production hookup. In Phase 1 tests, leave null. Phase 2 will
  /// wire this to `Sentry.captureException` once Sentry is initialized
  /// behind the Crashlytics opt-in flag.
  final void Function(SyncErrorEvent)? onError;

  final List<SyncErrorEvent> _buffer = <SyncErrorEvent>[];

  /// Hard cap on the in-memory buffer. When exceeded, oldest events drop
  /// first (FIFO). 100 is enough to cover a stuck-retry loop without
  /// ballooning RAM if the upload pipe is down for a long offline session.
  static const int _bufferCap = 100;

  /// Capture an error. The [category] is taken from the caller (typically
  /// [RetryPolicy.classify] in SyncWorker) so this class stays free of any
  /// retry-policy import — keeps the test surface small.
  ///
  /// Returns the constructed [SyncErrorEvent] so the caller can inspect or
  /// log it further if needed.
  SyncErrorEvent report(
    Object error,
    StackTrace stack, {
    SyncErrorCategory? category,
  }) {
    final SyncErrorCategory cat = category ?? SyncErrorCategory.unknown;
    final String stHash = _hash(stack.toString());
    final String raw = error.toString();
    final String truncated =
        raw.length > 256 ? '${raw.substring(0, 253)}...' : raw;

    final SyncErrorEvent event = SyncErrorEvent(
      timestamp: DateTime.now().toUtc(),
      category: cat,
      errorType: error.runtimeType.toString(),
      message: truncated,
      stackHash: stHash,
    );

    _buffer.add(event);
    if (_buffer.length > _bufferCap) {
      _buffer.removeAt(0);
    }
    onError?.call(event);
    return event;
  }

  /// Read-only view of the in-memory buffer. Newest event is last.
  List<SyncErrorEvent> get buffered => List.unmodifiable(_buffer);

  /// Drop all buffered events. Phase 2 will call this after a successful
  /// audit_events upload acknowledges the batch.
  void clear() => _buffer.clear();

  /// 64-bit FNV-1a → 16-char hex. Cheap, no `dart:crypto` dependency.
  /// Collisions are fine here — we use this only to dedupe stack traces in
  /// the audit log, not for any security claim.
  static String _hash(String s) {
    int h = 0xcbf29ce484222325;
    // 64-bit mask: (1 << 64) - 1, expressed without overflow.
    const int mask = 0xFFFFFFFFFFFFFFFF;
    for (final int c in s.codeUnits) {
      h ^= c;
      h = (h * 0x100000001b3) & mask;
    }
    final String hex = h.toRadixString(16).padLeft(16, '0');
    // Defensive substring guards against weird platforms returning >16 chars
    // (shouldn't happen with mask, but keeps the contract explicit).
    return hex.length > 16 ? hex.substring(0, 16) : hex;
  }
}
