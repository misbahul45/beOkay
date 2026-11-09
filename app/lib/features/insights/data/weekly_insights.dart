/// Ringkasan mingguan lintas domain. Deskriptif saja: tanpa korelasi, penilaian, atau skor kepatuhan.
class WeeklyInsights {
  const WeeklyInsights({
    required this.weekStart,
    required this.weekEnd,
    required this.recordedDays,
    required this.totalDays,
    required this.mealDays,
    required this.glucoseDays,
    required this.activityDays,
    required this.activityMinutes,
    required this.medScheduled,
    required this.medTaken,
    required this.medUnconfirmed,
    required this.freshness,
  });

  final String weekStart, weekEnd, freshness;
  final int recordedDays, totalDays, mealDays, glucoseDays, activityDays;
  final num? activityMinutes;
  final int medScheduled, medTaken, medUnconfirmed;

  bool get hasData => recordedDays > 0;

  factory WeeklyInsights.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic> m(String k) => (j[k] as Map).cast<String, dynamic>();
    return WeeklyInsights(
      weekStart: j['weekStart'] as String,
      weekEnd: j['weekEnd'] as String,
      recordedDays: j['recordedDays'] as int,
      totalDays: j['totalDays'] as int,
      mealDays: m('meals')['daysWithRecords'] as int,
      glucoseDays: m('glucose')['daysWithRecords'] as int,
      activityDays: m('activity')['daysWithRecords'] as int,
      activityMinutes: m('activity')['totalMinutes'] as num?,
      medScheduled: m('medication')['scheduled'] as int,
      medTaken: m('medication')['taken'] as int,
      medUnconfirmed: m('medication')['unconfirmed'] as int,
      freshness: (j['freshness'] as String?) ?? 'CURRENT',
    );
  }
}
