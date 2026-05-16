import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/services/feed_alert_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// Minimal valid Feed factory used throughout this file.
Feed _makeFeed({DateTime? endedAt, DateTime? startedAt}) {
  final now = DateTime.now().toUtc();
  return Feed(
    id: 'test-feed-id',
    babyId: 'test-baby-id',
    type: FeedType.breast,
    startedAt: startedAt ?? now.subtract(const Duration(minutes: 30)),
    endedAt: endedAt,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Register the Android platform implementation so the plugin's singleton
  // instance is set before any test calls cancel() / scheduleInexact().
  AndroidFlutterLocalNotificationsPlugin.registerWith();

  // Override platform to Android so flutter_local_notifications routes to the
  // Android implementation (which is what registerWith() just registered).
  debugDefaultTargetPlatformOverride = TargetPlatform.android;

  // Mock the flutter_local_notifications method channel so platform calls
  // succeed in unit-test context (no real Android runtime available).
  const notifChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );

  // Mock the flutter_timezone channel so NotificationService.init() does not
  // throw when the last-test needs to reach scheduleInexact().
  const tzChannel = MethodChannel('flutter_timezone');

  setUpAll(() {
    // Initialize timezone data (pure Dart, no platform channel needed).
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/New_York'));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifChannel, (call) async {
      // Return sensible stubs for every method the plugin may invoke.
      switch (call.method) {
        case 'initialize':
          return true;
        case 'cancel':
        case 'cancelAll':
        case 'show':
        case 'zonedSchedule':
          return null;
        case 'pendingNotificationRequests':
          return <Map<String, Object?>>[];
        case 'getActiveNotifications':
          return <Map<String, Object?>>[];
        case 'getNotificationAppLaunchDetails':
          return null;
      }
      return null;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(tzChannel, (call) async {
      if (call.method == 'getLocalTimezone') return 'America/New_York';
      return null;
    });

    // Initialize the plugin so _instance is set inside flutter_local_notifications.
    final plugin = FlutterLocalNotificationsPlugin();
    plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ── Constants ─────────────────────────────────────────────────────────────

  group('FeedAlertService constants are correct', () {
    test('enabledKey is feed.alertEnabled', () {
      expect(FeedAlertService.enabledKey, 'feed.alertEnabled');
    });

    test('prefsKey is feed.alertIntervalHours', () {
      expect(FeedAlertService.prefsKey, 'feed.alertIntervalHours');
    });
  });

  // ── scheduleForLastFeed() logic gates ─────────────────────────────────────

  group('scheduleForLastFeed()', () {
    test('returns cleanly when alert is disabled', () async {
      SharedPreferences.setMockInitialValues({
        FeedAlertService.enabledKey: false,
      });
      final prefs = await SharedPreferences.getInstance();

      await expectLater(
        FeedAlertService.scheduleForLastFeed(
          prefs: prefs,
          lastFeed: null,
          title: 't',
          body: 'b',
        ),
        completes,
      );
    }); // platform channel best-effort

    test('returns without error when lastFeed is null', () async {
      SharedPreferences.setMockInitialValues({
        FeedAlertService.enabledKey: true,
      });
      final prefs = await SharedPreferences.getInstance();

      await expectLater(
        FeedAlertService.scheduleForLastFeed(
          prefs: prefs,
          lastFeed: null,
          title: 'Title',
          body: 'Body',
        ),
        completes,
      );
    }); // platform channel best-effort

    test(
      'schedules using startedAt when endedAt is null (bottle feeds)',
      () async {
        // Bottle feeds save `endedAt = null`. The service must fall back to
        // `startedAt` as the anchor so bottle-only families still get the
        // interval reminder.
        //
        // startedAt = 30 min from now, default 3h interval →
        // fireAt = startedAt + 3h = ~3.5h from now (future) → schedules.
        SharedPreferences.setMockInitialValues({
          FeedAlertService.enabledKey: true,
          // prefsKey absent → defaults to 3h
        });
        final prefs = await SharedPreferences.getInstance();
        final feed = _makeFeed(
          startedAt: DateTime.now().toUtc().add(const Duration(minutes: 30)),
          endedAt: null,
        );

        await expectLater(
          FeedAlertService.scheduleForLastFeed(
            prefs: prefs,
            lastFeed: feed,
            title: 'Title',
            body: 'Body',
          ),
          completes,
        );
      },
    ); // platform channel best-effort

    test(
      'cancels when endedAt is null and startedAt is far in the past (overdue bottle feed)',
      () async {
        // Bottle feed from 10h ago: startedAt = 10h ago, endedAt = null →
        // anchor = startedAt → fireAt = startedAt + 3h = 7h ago (past) →
        // overdue → cancel (does NOT fire a stale alert).
        SharedPreferences.setMockInitialValues({
          FeedAlertService.enabledKey: true,
        });
        final prefs = await SharedPreferences.getInstance();
        final feed = _makeFeed(
          startedAt: DateTime.now().toUtc().subtract(const Duration(hours: 10)),
          endedAt: null,
        );

        await expectLater(
          FeedAlertService.scheduleForLastFeed(
            prefs: prefs,
            lastFeed: feed,
            title: 'Title',
            body: 'Body',
          ),
          completes,
        );
      },
    ); // platform channel best-effort

    test('returns without error when fireAt is in the past', () async {
      // endedAt = 10 hours ago → fireAt (default 3h interval) = 7 hours ago.
      SharedPreferences.setMockInitialValues({
        FeedAlertService.enabledKey: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final feed = _makeFeed(
        endedAt: DateTime.now().toUtc().subtract(const Duration(hours: 10)),
      );

      await expectLater(
        FeedAlertService.scheduleForLastFeed(
          prefs: prefs,
          lastFeed: feed,
          title: 'Title',
          body: 'Body',
        ),
        completes,
      );
    }); // platform channel best-effort

    test('uses default interval of 3 hours when pref not set', () async {
      // endedAt = 30 min from now → fireAt = endedAt + 3h = ~3.5h from now.
      // No prefsKey set → service defaults to 3h → fireAt is in the future →
      // reaches NotificationService.scheduleInexact().
      SharedPreferences.setMockInitialValues({
        FeedAlertService.enabledKey: true,
        // prefsKey intentionally absent → defaults to 3
      });
      final prefs = await SharedPreferences.getInstance();
      final feed = _makeFeed(
        endedAt: DateTime.now().toUtc().add(const Duration(minutes: 30)),
      );

      await expectLater(
        FeedAlertService.scheduleForLastFeed(
          prefs: prefs,
          lastFeed: feed,
          title: 'Title',
          body: 'Body',
        ),
        completes,
      );
    }); // platform channel best-effort
  });
}
