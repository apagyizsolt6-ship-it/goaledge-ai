import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _plugin.initialize(initSettings);
      final androidImpl =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();
      _initialized = true;
    } catch (_) {}
  }

  static Future<void> showAlert(int id, String title, String body) async {
    try {
      if (!_initialized) await init();
      const androidDetails = AndroidNotificationDetails(
        'goaledge_live_alerts',
        'GoalEdge Élő Riasztások',
        channelDescription: 'Értesítések gólokról és élő gólnyomásról',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      );
      const details = NotificationDetails(android: androidDetails);
      await _plugin.show(id, title, body, details);
    } catch (_) {}
  }
}
