import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Satu notifikasi lokal yang akan muncul pada instan UTC [at]. Teks layar kunci sudah dibuat server
/// dan tidak memuat nama obat atau nilai kesehatan.
class ScheduledReminder {
  const ScheduledReminder({
    required this.at,
    required this.title,
    required this.body,
  });
  final DateTime at;
  final String title;
  final String body;
}

/// Batas perangkat: iOS hanya mengizinkan 64 notifikasi tertunda; satu angka aman untuk semua platform.
const maxScheduledReminders = 60;

abstract interface class ReminderScheduler {
  /// True bila pengguna mengizinkan notifikasi.
  Future<bool> requestPermission();

  /// Mengganti seluruh jadwal dengan [items] (yang sudah lewat dibuang, maksimal [maxScheduledReminders]).
  Future<void> replaceAll(List<ScheduledReminder> items);
  Future<void> cancelAll();
}

/// Implementasi nyata memakai flutter_local_notifications. Tanpa izin alarm eksak: penyampaian bisa
/// bergeser beberapa menit (mode inexact), yang cukup untuk pengingat catatan harian.
class LocalNotificationsScheduler implements ReminderScheduler {
  LocalNotificationsScheduler([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(
      tz.UTC,
    ); // instan absolut dari server (UTC); zona tampilan tidak diperlukan
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_beokay'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  @override
  Future<bool> requestPermission() async {
    await _init();
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, sound: true) ??
          false;
    }
    return false;
  }

  @override
  Future<void> replaceAll(List<ScheduledReminder> items) async {
    await _init();
    await _plugin.cancelAll();
    final now = DateTime.now().toUtc();
    final upcoming = items
        .where((i) => i.at.isAfter(now))
        .take(maxScheduledReminders)
        .toList();
    for (var i = 0; i < upcoming.length; i++) {
      final item = upcoming[i];
      await _plugin.zonedSchedule(
        id: i + 1,
        title: item.title,
        body: item.body,
        scheduledDate: tz.TZDateTime.from(item.at, tz.UTC),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'beokay_reminders',
            'Pengingat',
            channelDescription: 'Pengingat mencatat dari beOkay',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            visibility: NotificationVisibility.private,
            icon: 'ic_stat_beokay',
            color: Color(0xFF16796F),
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  @override
  Future<void> cancelAll() async {
    await _init();
    await _plugin.cancelAll();
  }
}

final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => LocalNotificationsScheduler(),
);
