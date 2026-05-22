import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Captures errors encountered during the deferred boot phase (Supabase init,
/// WorkManager registration, RevenueCat configure, Sentry init).
///
/// Surfaced via Settings → About → Diagnostics so a user reporting "sync
/// doesn't work" can show us *which* boot step failed, instead of every
/// failure being indistinguishable. Replaces the bare `catch (_) {}` swallow
/// that previously hid these errors entirely in release builds.
class BootDiagnostics {
  BootDiagnostics._();

  /// Process-global singleton. Updated from `main.dart` during deferred boot
  /// and read by [bootDiagnosticsProvider] for UI rendering.
  static final instance = BootDiagnostics._();

  final Map<String, String> _errors = <String, String>{};

  /// Records that boot stage [stage] failed with [error]. Subsequent reads of
  /// [bootDiagnosticsProvider] reflect the new entry on next invalidation.
  void recordError(String stage, Object error, [StackTrace? st]) {
    _errors[stage] = '$error';
    debugPrint('[boot] $stage failed: $error');
    if (st != null && kDebugMode) debugPrintStack(stackTrace: st, label: 'boot:$stage');
  }

  Map<String, String> snapshot() => Map.unmodifiable(_errors);
}

/// Read-only view of the boot diagnostics map. Diagnostics screens watch this
/// to render a "what went wrong at startup" list.
final bootDiagnosticsProvider = Provider<Map<String, String>>((ref) {
  return BootDiagnostics.instance.snapshot();
});
