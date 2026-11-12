import '../../../core/ids/record_id.dart';

import '../../../core/network/account_scoped_repository.dart';

enum CoachingSlot {
  morning('MORNING', 'Pagi', '07.00'),
  midday('MIDDAY', 'Siang', '12.00'),
  afternoon('AFTERNOON', 'Sore', '16.00'),
  evening('EVENING', 'Malam', '19.00');

  const CoachingSlot(this.wire, this.label, this.time);
  final String wire, label, time;

  static CoachingSlot? parse(String? v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    return null;
  }
}

class DayState {
  DayState.fromJson(Map<String, dynamic> j)
    : date = j['date'] as String,
      state = j['state'] as String,
      today = j['today'] == true;
  final String date, state;
  final bool today;
  bool get done => state == 'OBSERVED' || state == 'USER_CONFIRMED';
}

class CoachingAction {
  CoachingAction.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      source = j['source'] as String,
      kind = j['kind'] as String,
      title = j['title'] as String,
      rationale = (j['rationale'] as String?) ?? '',
      evidence = ((j['evidence'] as Map?)?['summary'] as String?) ?? '',
      window = ((j['evidence'] as Map?)?['window'] as String?) ?? '',
      memories = [
        for (final m
            in ((j['evidence'] as Map?)?['memories'] as List? ?? const []))
          m as String,
      ],
      slot = CoachingSlot.parse(j['slot'] as String?),
      startDate = j['startDate'] as String,
      endDate = j['endDate'] as String,
      days = (j['days'] as int?) ?? 1,
      status = j['status'] as String,
      phase = j['phase'] as String,
      dayStates = [
        for (final d in (j['dayStates'] as List? ?? const []))
          DayState.fromJson(d as Map<String, dynamic>),
      ],
      reminderTime = (j['reminder'] as Map?)?['localTime'] as String?;
  final String id, source, kind, title, rationale, evidence, window;
  final List<String> memories;
  final CoachingSlot? slot;
  final String startDate, endDate, status, phase;
  final int days;
  final List<DayState> dayStates;
  final String? reminderTime;

  bool get proposed => status == 'PROPOSED';
  bool get running => phase == 'RUNNING';
  bool get isActivity => kind == 'ACTIVITY_SESSION';
  bool get isHabit => kind == 'HABIT_STEP';
  DayState? get todayState {
    for (final d in dayStates) {
      if (d.today) return d;
    }
    return null;
  }
}

class ReflectionStatus {
  ReflectionStatus.fromJson(Map<String, dynamic> j)
    : weekStart = j['weekStart'] as String,
      weekEnd = j['weekEnd'] as String,
      done = j['done'] == true,
      available = j['available'] == true;
  final String weekStart, weekEnd;
  final bool done, available;
}

class CoachingOverview {
  CoachingOverview.fromJson(Map<String, dynamic> j)
    : consentRequired = j['consentRequired'] == true,
      opportunities = [
        for (final v in (j['opportunities'] as List? ?? const []))
          CoachingAction.fromJson(v as Map<String, dynamic>),
      ],
      actions = [
        for (final v in (j['actions'] as List? ?? const []))
          CoachingAction.fromJson(v as Map<String, dynamic>),
      ],
      reflection = j['reflection'] is Map
          ? ReflectionStatus.fromJson(j['reflection'] as Map<String, dynamic>)
          : null,
      slot = CoachingSlot.parse((j['preferences'] as Map?)?['slot'] as String?);
  final bool consentRequired;
  final List<CoachingAction> opportunities, actions;
  final ReflectionStatus? reflection;
  final CoachingSlot? slot;

  List<CoachingAction> get running => actions.where((a) => a.running).toList();
  List<CoachingAction> get ended => actions.where((a) => !a.running).toList();
}

class GoalAdjustment {
  GoalAdjustment.fromJson(Map<String, dynamic> j)
    : goalId = j['goalId'] as String,
      title = j['title'] as String,
      goalType = j['goalType'] as String,
      fromTarget = (j['fromTarget'] as num).toDouble(),
      toTarget = (j['toTarget'] as num).toDouble(),
      basis = (j['basis'] as String?) ?? '',
      direction = (j['direction'] as String?) ?? 'DOWN';
  final String goalId, title, goalType, basis, direction;
  bool get raises => direction == 'UP';
  final double fromTarget, toTarget;

  String _fmt(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';
  String get unit => switch (goalType) {
    'activity_minutes' => 'menit',
    'walking_sessions' => 'sesi',
    'record_meals' => 'hari',
    _ => 'kali',
  };
  String get change => '${_fmt(fromTarget)} → ${_fmt(toTarget)} $unit';
}

class ReflectionGoal {
  ReflectionGoal.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      title = j['title'] as String,
      goalType = j['goalType'] as String,
      period = j['period'] as String,
      target = (j['target'] as num).toDouble(),
      value = (j['value'] as num?)?.toDouble(),
      ratio = (j['ratio'] as num?)?.toDouble();
  final String id, title, goalType, period;
  final double target;
  final double? value, ratio;
}

class Checkin {
  Checkin.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      weekStart = j['weekStart'] as String,
      mood = j['mood'] as String?;
  final String id, weekStart;
  final String? mood;
}

class Strategy {
  Strategy.fromJson(Map<String, dynamic> j)
    : key = j['key'] as String,
      title = j['title'] as String,
      detail = j['detail'] as String;
  final String key, title, detail;
}

class PreviousStrategy {
  PreviousStrategy.fromJson(Map<String, dynamic> j)
    : title = j['title'] as String,
      barrierLabel = j['barrierLabel'] as String?,
      confirmedDays = (j['confirmedDays'] as int?) ?? 0,
      days = (j['days'] as int?) ?? 7;
  final String title;
  final String? barrierLabel;
  final int confirmedDays, days;
}

class Reflection {
  Reflection.fromJson(Map<String, dynamic> j)
    : consentRequired = j['consentRequired'] == true,
      weekStart = (j['weekStart'] as String?) ?? '',
      weekEnd = (j['weekEnd'] as String?) ?? '',
      done = j['done'] is Map
          ? Checkin.fromJson(j['done'] as Map<String, dynamic>)
          : null,
      recordedDays = ((j['summary'] as Map?)?['recordedDays'] as int?) ?? 0,
      totalDays = ((j['summary'] as Map?)?['totalDays'] as int?) ?? 7,
      goals = [
        for (final g in (j['goals'] as List? ?? const []))
          ReflectionGoal.fromJson(g as Map<String, dynamic>),
      ],
      observed = ((j['actions'] as Map?)?['observed'] as int?) ?? 0,
      confirmed = ((j['actions'] as Map?)?['confirmed'] as int?) ?? 0,
      notObserved = ((j['actions'] as Map?)?['notObserved'] as int?) ?? 0,
      planned = ((j['actions'] as Map?)?['planned'] as int?) ?? 0,
      fromAssistant = ((j['actions'] as Map?)?['fromAssistant'] as int?) ?? 0,
      actionTitles = [
        for (final a in ((j['actions'] as Map?)?['items'] as List? ?? const []))
          (a as Map)['title'] as String,
      ],
      positives = [
        for (final p in (j['positives'] as List? ?? const [])) p as String,
      ],
      adjustments = [
        for (final a in (j['adjustments'] as List? ?? const []))
          GoalAdjustment.fromJson(a as Map<String, dynamic>),
      ],
      strategies = {
        for (final e
            in (((j['strategies'] as Map?)?['byBarrier'] as Map?) ?? const {})
                .entries)
          e.key as String: [
            for (final s in e.value as List)
              Strategy.fromJson(s as Map<String, dynamic>),
          ],
      },
      strategiesReviewed =
          (j['strategies'] as Map?)?['reviewStatus'] == 'CLINICALLY_REVIEWED',
      previousStrategy = j['previousStrategy'] is Map
          ? PreviousStrategy.fromJson(
              j['previousStrategy'] as Map<String, dynamic>,
            )
          : null,
      learned = [
        for (final l
            in (((j['learned'] as Map?)?['lines'] as List?) ?? const []))
          l as String,
      ],
      memoryBarriers = [
        for (final b in (j['memoryBarriers'] as List? ?? const [])) b as String,
      ],
      streak = (j['streak'] as int?) ?? 0,
      memoryAvailable = j['memoryAvailable'] == true,
      preferredSlot = CoachingSlot.parse(j['preferredSlot'] as String?);
  final bool consentRequired;
  final String weekStart, weekEnd;
  final Checkin? done;
  final int recordedDays, totalDays;
  final List<ReflectionGoal> goals;
  final int observed, confirmed, notObserved, planned, fromAssistant;
  final List<String> actionTitles, positives;
  final List<GoalAdjustment> adjustments;
  final Map<String, List<Strategy>> strategies;
  final bool strategiesReviewed;
  final PreviousStrategy? previousStrategy;
  final List<String> learned, memoryBarriers;
  final int streak;
  final bool memoryAvailable;
  final CoachingSlot? preferredSlot;

  int get actionsDone => observed + confirmed + fromAssistant;
}

class CheckinResult {
  CheckinResult.fromJson(Map<String, dynamic> j)
    : recognition = [
        for (final r in (j['recognition'] as List? ?? const [])) r as String,
      ];
  final List<String> recognition;
}

class CoachingRepository extends AccountScopedRepository {
  CoachingRepository(super.api, {required super.isCurrentAccount});

  Future<CoachingOverview> overview() async =>
      CoachingOverview.fromJson((await api.get('/api/me/coaching')).object);

  Future<CoachingAction> accept(
    String id, {
    CoachingSlot? slot,
    bool reminder = false,
  }) async => CoachingAction.fromJson(
    (await write('POST', '/api/me/coaching/actions/$id/decision', {
      'operationId': newRecordId(),
      'decision': 'ACCEPT',
      'slot': ?slot?.wire,
      if (reminder) 'reminder': <String, dynamic>{},
    })).object,
  );

  Future<CoachingAction> withdraw(String id) async => CoachingAction.fromJson(
    (await write('POST', '/api/me/coaching/actions/$id/decision', {
      'operationId': newRecordId(),
      'decision': 'WITHDRAW',
    })).object,
  );

  Future<CoachingAction> feedback(
    String id,
    String kind, {
    CoachingSlot? slot,
  }) async => CoachingAction.fromJson(
    (await write('POST', '/api/me/coaching/actions/$id/feedback', {
      'operationId': newRecordId(),
      'kind': kind,
      'slot': ?slot?.wire,
    })).object,
  );

  Future<CoachingAction> confirm(String id, String date) async =>
      CoachingAction.fromJson(
        (await write('POST', '/api/me/coaching/actions/$id/confirm', {
          'operationId': newRecordId(),
          'date': date,
        })).object,
      );

  Future<Reflection> reflection() async =>
      Reflection.fromJson((await api.get('/api/me/coaching/checkins')).object);

  Future<CheckinResult> submitCheckin({
    required String operationId,
    required String weekStart,
    String? mood,
    List<String> hardest = const [],
    String? note,
    List<GoalAdjustment> adjustments = const [],
    CoachingSlot? preferredSlot,
    bool rememberSlot = false,
    ({String barrier, String key})? strategy,
  }) async => CheckinResult.fromJson(
    (await write('POST', '/api/me/coaching/checkins', {
      'operationId': operationId,
      'weekStart': weekStart,
      'mood': ?mood,
      'hardest': hardest,
      'note': ?note,
      'adjustments': [
        for (final a in adjustments)
          {'goalId': a.goalId, 'toTarget': a.toTarget},
      ],
      'preferredSlot': ?preferredSlot?.wire,
      if (preferredSlot != null) 'rememberSlot': rememberSlot,
      if (strategy != null)
        'strategy': {'barrier': strategy.barrier, 'key': strategy.key},
    })).object,
  );
}
