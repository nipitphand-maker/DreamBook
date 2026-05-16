import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// SharedPreferences key for the user's preferred day-start hour.
const String kDayStartHour = 'settings.dayStartHour';

/// The hour (0–23) at which a new logical day begins.
///
/// Default is 6 (6 AM), matching Huckleberry's industry standard.
/// Sessions started before this hour are attributed to the previous
/// calendar day.
final dayStartHourProvider = Provider<int>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getInt(kDayStartHour) ?? 6;
});
