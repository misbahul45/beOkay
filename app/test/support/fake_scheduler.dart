import 'package:app/core/notifications/reminder_scheduler.dart';

/// Penjadwal palsu untuk tes: tidak menyentuh plugin platform.
class FakeReminderScheduler implements ReminderScheduler {
  final List<ScheduledReminder> scheduled = [];
  int cancelCount = 0;
  bool permission = true;
  @override
  Future<bool> requestPermission() async => permission;
  @override
  Future<void> replaceAll(List<ScheduledReminder> items) async {
    scheduled
      ..clear()
      ..addAll(items);
  }

  @override
  Future<void> cancelAll() async {
    cancelCount++;
    scheduled.clear();
  }
}
