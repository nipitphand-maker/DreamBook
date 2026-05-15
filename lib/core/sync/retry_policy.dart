import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Whether an exception should be retried (transient) or fail-fast (terminal).
enum RetryClass { transient, terminal }

/// Wraps async operations with exponential backoff + jitter.
/// Transient errors retry up to [maxAttempts] times; terminal errors fail immediately.
class RetryPolicy {
  /// Classify whether [e] is worth retrying.
  /// Transient: SocketException, TimeoutException, PostgrestException
  /// with code 5xx / 408 / 429 / PGRST204.
  /// Terminal: TypeError (programming error), PostgrestException 4xx
  /// (except 408/429), and anything else (fail loud by default).
  static RetryClass classify(Object e) {
    if (e is SocketException || e is TimeoutException) {
      return RetryClass.transient;
    }
    if (e is PostgrestException) {
      final code = e.code ?? '';
      if (code == 'PGRST204' || code == '408' || code == '429') {
        return RetryClass.transient;
      }
      // Numeric code: 5xx → transient, 4xx → terminal, anything else → terminal.
      final n = int.tryParse(code);
      if (n != null && n >= 500 && n < 600) return RetryClass.transient;
      return RetryClass.terminal;
    }
    if (e is TypeError) return RetryClass.terminal;
    return RetryClass.terminal;
  }

  /// Compute backoff for the [attempt]-th retry (1-indexed: attempt=1 → 1s,
  /// attempt=2 → 2s, ...). Caps at 16s (attempt >= 5). Adds ±20% random
  /// jitter. Pure function — pass [random] for deterministic tests.
  static Duration delayFor(int attempt, {Random? random}) {
    if (attempt < 1) return Duration.zero;
    final capped = attempt > 5 ? 5 : attempt;
    final base = Duration(seconds: 1 << (capped - 1)); // 1, 2, 4, 8, 16 seconds
    final r = random ?? _defaultRandom;
    final jitterFactor = 0.8 + r.nextDouble() * 0.4; // 0.8 .. 1.2
    final ms = (base.inMilliseconds * jitterFactor).round();
    return Duration(milliseconds: ms);
  }

  static final Random _defaultRandom = Random();

  /// Run [body] with retry. Returns body's result on success.
  /// Throws the last error on exhaustion ([maxAttempts] attempts), or
  /// immediately rethrows on terminal error.
  /// Each delay between attempts uses [delayFor] (with random jitter) by
  /// default; pass [delayFn] / [sleep] for tests.
  static Future<T> run<T>(
    Future<T> Function() body, {
    int maxAttempts = 5,
    Future<void> Function(Duration)? sleep,
    Duration Function(int attempt)? delayFn,
  }) async {
    Object? lastError;
    StackTrace? lastStack;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await body();
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        if (classify(e) == RetryClass.terminal) rethrow;
        if (attempt == maxAttempts) break;
        final d = (delayFn ?? delayFor)(attempt);
        await (sleep ?? Future<void>.delayed)(d);
      }
    }
    Error.throwWithStackTrace(lastError!, lastStack!);
  }
}
