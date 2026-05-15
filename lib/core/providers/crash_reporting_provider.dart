import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';

const _kSentryOptIn = 'sentry_opt_in';

final crashReportingEnabledProvider = Provider<bool>((ref) {
  return ref.watch(sharedPreferencesProvider).getBool(_kSentryOptIn) ?? false;
});

final crashReportingNotifierProvider =
    Provider<CrashReportingNotifier>((ref) => CrashReportingNotifier(ref));

class CrashReportingNotifier {
  CrashReportingNotifier(this._ref);
  final Ref _ref;

  Future<void> setEnabled(bool value) async {
    await _ref.read(sharedPreferencesProvider).setBool(_kSentryOptIn, value);
    _ref.invalidate(crashReportingEnabledProvider);
  }
}
