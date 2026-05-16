import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kInstallDateKey = 'rating.install_date';
const _kLastRequestedKey = 'rating.last_requested_at';
const _kMinInstallDays = 5;
const _kCooldownDays = 90;

class RatingService {
  Future<void> maybeRequest(SharedPreferences prefs) async {
    _recordInstallDate(prefs);

    if (!_installedLongEnough(prefs)) return;
    if (_requestedRecently(prefs)) return;
    if (_outsideQuietHours()) return;

    final inAppReview = InAppReview.instance;
    if (!await inAppReview.isAvailable()) return;

    await prefs.setString(_kLastRequestedKey, DateTime.now().toIso8601String());
    await inAppReview.requestReview();
  }

  void _recordInstallDate(SharedPreferences prefs) {
    if (!prefs.containsKey(_kInstallDateKey)) {
      prefs.setString(_kInstallDateKey, DateTime.now().toIso8601String());
    }
  }

  bool _installedLongEnough(SharedPreferences prefs) {
    final raw = prefs.getString(_kInstallDateKey);
    if (raw == null) return false;
    final installed = DateTime.tryParse(raw);
    if (installed == null) return false;
    return DateTime.now().difference(installed).inDays >= _kMinInstallDays;
  }

  bool _requestedRecently(SharedPreferences prefs) {
    final raw = prefs.getString(_kLastRequestedKey);
    if (raw == null) return false;
    final last = DateTime.tryParse(raw);
    if (last == null) return false;
    return DateTime.now().difference(last).inDays < _kCooldownDays;
  }

  // Only prompt during waking hours — parents are active, not stressed at 3am.
  bool _outsideQuietHours() {
    final hour = DateTime.now().hour;
    return hour < 6 || hour >= 21;
  }
}
