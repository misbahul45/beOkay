import '../../../core/network/account_scoped_repository.dart';
import '../../../core/notifications/reminder_scheduler.dart';

const reminderKindLabels = {
  'medication': 'Obat',
  'glucose': 'Glukosa',
  'meal': 'Makan',
  'activity': 'Aktivitas',
  'goal': 'Tujuan',
  'custom': 'Lainnya',
};
const weekdayShort = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

class Reminder {
  Reminder.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      kind = j['kind'] as String,
      title = j['title'] as String,
      localTime = j['localTime'] as String,
      daysOfWeek = [
        for (final d in (j['daysOfWeek'] as List)) (d as num).toInt(),
      ],
      enabled = j['enabled'] as bool,
      version = j['version'] as int;
  final String id, kind, title, localTime;
  final List<int> daysOfWeek;
  final bool enabled;
  final int version;

  String get daysLabel => daysOfWeek.length == 7
      ? 'Setiap hari'
      : daysOfWeek.map((d) => weekdayShort[d - 1]).join(', ');
}

class ReminderRules {
  const ReminderRules(this.items, this.limit);
  final List<Reminder> items;
  final int limit;
}

class RemindersRepository extends AccountScopedRepository {
  RemindersRepository(
    super.api, {
    required super.isCurrentAccount,
    super.enqueueOffline,
  });

  Future<ReminderRules> list() async {
    final r = (await api.get('/api/me/reminders')).object;
    return ReminderRules([
      for (final v in (r['items'] as List))
        Reminder.fromJson(v as Map<String, dynamic>),
    ], (r['limit'] as num).toInt());
  }

  Future<Reminder> create({
    required String kind,
    required String title,
    required String localTime,
    required List<int> days,
  }) async => Reminder.fromJson(
    (await write('POST', '/api/me/reminders', {
      'kind': kind,
      'title': title,
      'localTime': localTime,
      'daysOfWeek': days,
    })).object,
  );

  Future<void> update(Reminder r, Map<String, dynamic> changes) async => write(
    'PATCH',
    '/api/me/reminders/${r.id}',
    {'expectedVersion': r.version, ...changes},
  );

  /// Kejadian untuk dijadwalkan sebagai notifikasi lokal; teks layar kunci berasal dari server.
  Future<List<ScheduledReminder>> upcoming({int days = 7}) async {
    final r = (await api.get('/api/me/reminders/upcoming?days=$days')).object;
    return [
      for (final v in (r['items'] as List))
        ScheduledReminder(
          at: DateTime.parse(
            (v as Map<String, dynamic>)['at'] as String,
          ).toUtc(),
          title: v['title'] as String,
          body: v['body'] as String,
        ),
    ];
  }

  Future<List<ScheduledReminder>> medicationOccurrences({int days = 2}) async {
    final r = (await api.get('/api/me/medications/upcoming?days=$days')).object;
    return [
      for (final v in (r['items'] as List).cast<Map<String, dynamic>>())
        ScheduledReminder(
          at: DateTime.parse(v['scheduledAt'] as String).toUtc(),
          title: v['title'] as String,
          body: v['body'] as String,
          medication: MedicationRef(
            v['regimenId'] as String,
            v['scheduleId'] as String,
            v['scheduledAt'] as String,
          ),
        ),
    ];
  }
}
