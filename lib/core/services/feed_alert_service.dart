import 'package:dreambook/core/models/feed.dart';
import 'package:dreambook/core/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FeedAlertService {
  FeedAlertService._();

  static const int _notifId = 200;
  static const String prefsKey = 'feed.alertIntervalHours';
  static const String enabledKey = 'feed.alertEnabled';

  /// Schedules (or cancels) a feed-interval notification based on [lastFeed].
  ///
  /// [title] and [body] are supplied by the caller so they can be localised at
  /// schedule time; the OS fires them later outside any Flutter context.
  static Future<void> scheduleForLastFeed({
    required SharedPreferences prefs,
    required Feed? lastFeed,
    required String title,
    required String body,
  }) async {
    final enabled = prefs.getBool(enabledKey) ?? true;
    if (!enabled) {
      await cancel();
      return;
    }

    if (lastFeed == null) {
      await cancel();
      return;
    }

    final intervalHours = prefs.getInt(prefsKey) ?? 3;
    // Bottle feeds save `endedAt = null`; for them the "finished eating" anchor
    // is effectively `startedAt` (a few minutes off, dwarfed by the 3–5h
    // interval). Falling back ensures bottle-only families still get reminders.
    final anchor = lastFeed.endedAt ?? lastFeed.startedAt;
    final fireAt = anchor.add(Duration(hours: intervalHours));

    if (!fireAt.isAfter(DateTime.now())) {
      // Overdue — don't fire a stale alert.
      await cancel();
      return;
    }

    await NotificationService.scheduleInexact(
      id: _notifId,
      title: title,
      body: body,
      when: fireAt,
    );
  }

  static Future<void> cancel() => NotificationService.cancel(_notifId);
}
