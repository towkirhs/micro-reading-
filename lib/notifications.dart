import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Thin wrapper around flutter_local_notifications.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Called with the book id when a notification is tapped.
  void Function(String bookId)? onOpen;

  static const int snoozeId = 99;
  static const int testId = 98;

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reading',
      'Reading nudges',
      channelDescription: 'A short piece of your book, at a random moment.',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final dynamic zone = await FlutterTimezone.getLocalTimezone();
      final String name = zone is String ? zone : zone.identifier as String;
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // Fall back to a fixed whole-hour offset (e.g. UTC+6 -> Etc/GMT-6).
      final hours = DateTime.now().timeZoneOffset.inHours;
      final sign = hours <= 0 ? '+' : '-';
      tz.setLocalLocation(tz.getLocation('Etc/GMT$sign${hours.abs()}'));
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null) onOpen?.call(payload);
      },
    );
  }

  /// Book id of the notification that launched the app, if any.
  Future<String?> launchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details != null && details.didNotificationLaunchApp) {
      return details.notificationResponse?.payload;
    }
    return null;
  }

  Future<void> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
  }

  Future<void> schedule({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    required String bookId,
  }) async {
    final date = tz.TZDateTime.from(when, tz.local);
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        date,
        _details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: bookId,
      );
    } catch (_) {
      // Exact alarms not allowed: an inexact one is still better than none.
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        date,
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: bookId,
      );
    }
  }

  Future<void> cancel(int id) => _plugin.cancel(id);
}
