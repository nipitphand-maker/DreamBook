import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// SharedPreferences key for the user's preferred day-start hour.
const String kDayStartHour = 'settings.dayStartHour';

/// The hour (0–23) at which a new logical day begins.
///
/// Default is 0 (midnight) — matches the user's naive expectation that
/// "today" starts at the calendar boundary. Users who do overnight feeds
/// can switch to 3/5/6/7/8 AM via Settings so a 2 AM session is attributed
/// to the same logical day as the prior evening.
final dayStartHourProvider = Provider<int>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getInt(kDayStartHour) ?? 0;
});
