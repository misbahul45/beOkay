import '../../../core/network/account_scoped_repository.dart';

const goalTypes = {
  'manual_checkins': 'Check-in manual',
  'activity_minutes': 'Menit aktivitas',
  'walking_sessions': 'Sesi jalan kaki',
  'record_meals': 'Mencatat makanan',
  'record_glucose': 'Mencatat glukosa',
};
const goalTypeHints = {
  'manual_checkins': 'Kamu mencatat sendiri tiap kali melakukannya.',
  'activity_minutes': 'Dihitung otomatis dari sesi aktivitas yang kamu catat.',
  'walking_sessions': 'Dihitung otomatis dari sesi jalan kaki.',
  'record_meals': 'Jumlah hari kamu mencatat makanan.',
  'record_glucose':
      'Jumlah hari kamu mencatat glukosa. Bukan target nilai glukosa.',
};

class GoalProgress {
  GoalProgress.fromJson(Map<String, dynamic> j)
    : value = j['value'] as num?,
      target = j['targetValue'] as num,
      ratio = j['ratio'] as num?,
      sourceCount = j['sourceCount'] as int,
      periodStart = j['periodStart'] as String,
      periodEnd = j['periodEnd'] as String;
  final num? value;
  final num target;
  final num? ratio;
  final int sourceCount;
  final String periodStart, periodEnd;
}

class Goal {
  Goal.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      title = j['title'] as String,
      type = j['goalType'] as String,
      target = j['targetValue'] as num,
      period = j['period'] as String,
      status = j['status'] as String,
      version = j['version'] as int,
      progress = j['progress'] is Map<String, dynamic>
          ? GoalProgress.fromJson(j['progress'] as Map<String, dynamic>)
          : null;
  final String id, title, type, period, status;
  final num target;
  final int version;
  final GoalProgress? progress;
  bool get manual => type == 'manual_checkins';
  String get periodLabel => period == 'weekly' ? 'per minggu' : 'per hari';
}

class GoalsRepository extends AccountScopedRepository {
  GoalsRepository(
    super.api, {
    required super.isCurrentAccount,
    super.enqueueOffline,
  });
  Future<List<Goal>> list() async =>
      ((await api.get('/api/me/goals?limit=50')).object['items'] as List)
          .map((v) => Goal.fromJson(v as Map<String, dynamic>))
          .toList();
  Future<void> create(Map<String, dynamic> body) async =>
      write('POST', '/api/me/goals', body);
  Future<void> update(String id, Map<String, dynamic> body) async =>
      write('PATCH', '/api/me/goals/$id', body);
  Future<void> checkin(String goalId, Map<String, dynamic> body) async => write(
    'POST',
    '/api/me/goals/$goalId/checkins',
    body,
    queue: (
      domain: 'goal_checkin',
      recordId: body['id'] as String,
      parentId: goalId,
    ),
  );
}
