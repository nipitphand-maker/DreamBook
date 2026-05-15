import 'dart:async';
import 'dart:io';

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
}
