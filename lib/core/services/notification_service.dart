import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String defaultChannelId = 'dreambook_default_v1';
  static const String defaultChannelName = 'DreamBook reminders';
  static const String defaultChannelDesc =
      'Gentle, inexact reminders for pumping and stash expiry.';

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    final tzName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(tzName));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestSoundPermission: false,
      requestBadgePermission: false,
      requestAlertPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
    );
  }

  static Future<bool> requestPermissions() async {
    final iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    final iosGrant = await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        true;

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final andGrant =
        await androidPlugin?.requestNotificationsPermission() ?? true;
    // NOTE: deliberately do NOT call requestExactAlarmsPermission().
    return iosGrant && andGrant;
  }

  /// Schedule an inexact one-shot notification.
  /// Never accepts an exact mode — caller cannot opt into precise timing.
  static Future<void> scheduleInexact({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    final scheduled = tz.TZDateTime.from(when, tz.local);
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          defaultChannelId,
          defaultChannelName,
          channelDescription: defaultChannelDesc,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  static Future<void> cancel(int id) => _plugin.cancel(id: id);

  static Future<void> cancelAll() => _plugin.cancelAll();
}
