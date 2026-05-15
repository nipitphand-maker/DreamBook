import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Sensitive field names stripped from Sentry payloads before upload.
const _sensitiveFields = {
  'ciphertext',
  'aad_hash',
  'wrapped_key',
  'device_fp',
};

bool _containsSensitiveKey(String key) =>
    _sensitiveFields.contains(key) ||
    key.endsWith('_key') ||
    key.endsWith('_fp');

dynamic _scrub(dynamic value) {
  if (value is Map<String, dynamic>) {
    return {
      for (final e in value.entries)
        e.key: _containsSensitiveKey(e.key) ? '[REDACTED]' : _scrub(e.value),
    };
  }
  if (value is List) return value.map(_scrub).toList();
  return value;
}

SentryEvent? _beforeSend(SentryEvent event, Hint hint) {
  final extra = event.extra;
  if (extra == null) return event;
  return event.copyWith(extra: _scrub(extra) as Map<String, dynamic>?);
}

/// Initialises Sentry with PII scrubbing. [dsn] comes from the `.env` asset.
/// Crash reporting is opt-in: call only when the user has consented.
Future<void> initSentry({
  required String dsn,
  bool debug = kDebugMode,
}) async {
  await SentryFlutter.init(
    (options) {
      options.dsn = dsn;
      options.debug = debug;
      options.tracesSampleRate = 0.0; // no performance tracing — privacy first
      options.beforeSend = _beforeSend;
    },
  );
}

/// Exposed for testing only. In production, use [initSentry].
SentryEvent? sentryBeforeSendForTest(SentryEvent event, Hint hint) =>
    _beforeSend(event, hint);
