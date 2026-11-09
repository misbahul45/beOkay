/// Tren harian lintas domain dari server. Nilai null = tidak tercatat/tidak diketahui (bukan nol).
class TrendDay {
  TrendDay.fromJson(Map<String, dynamic> j)
    : date = DateTime.parse(j['date'] as String),
      recorded = j['recorded'] as bool,
      glucoseCount = (j['glucose'] as Map?)?['count'] as int?,
      glucoseMin = ((j['glucose'] as Map?)?['min'] as num?)?.toDouble(),
      glucoseMax = ((j['glucose'] as Map?)?['max'] as num?)?.toDouble(),
      activityMinutes = j['activityMinutes'] as int?,
      mealCount = (j['meals'] as Map)['count'] as int,
      carbs = (((j['meals'] as Map)['carbs'] as Map?)?['value'] as num?)?.toDouble(),
      carbsCoverage = ((j['meals'] as Map)['carbs'] as Map?)?['coverage'] as String?,
      medTaken = (j['medication'] as Map)['taken'] as int,
      medSkipped = (j['medication'] as Map)['skipped'] as int;

  final DateTime date;
  final bool recorded;
  final int? glucoseCount, activityMinutes;
  final double? glucoseMin, glucoseMax, carbs;
  final String? carbsCoverage;
  final int mealCount, medTaken, medSkipped;
}

sealed class TrendNote {
  const TrendNote();
  factory TrendNote.fromJson(Map<String, dynamic> j) => switch (j['code']) {
    'STREAK' => StreakNote(j['days'] as int),
    'ACTIVITY_MORE' => ActivityMoreNote(j['current'] as int, j['previous'] as int),
    'ACTIVITY_PERSONAL_BEST_DAY' => PersonalBestNote(DateTime.parse(j['date'] as String), j['minutes'] as int),
    'MORE_DAYS_RECORDED' => MoreDaysNote(j['current'] as int, j['previous'] as int),
    _ => const UnknownNote(),
  };
}

class StreakNote extends TrendNote {
  const StreakNote(this.days);
  final int days;
}

class ActivityMoreNote extends TrendNote {
  const ActivityMoreNote(this.current, this.previous);
  final int current, previous;
}

class PersonalBestNote extends TrendNote {
  const PersonalBestNote(this.date, this.minutes);
  final DateTime date;
  final int minutes;
}

class MoreDaysNote extends TrendNote {
  const MoreDaysNote(this.current, this.previous);
  final int current, previous;
}

class UnknownNote extends TrendNote {
  const UnknownNote();
}

class Trends {
  Trends.fromJson(Map<String, dynamic> j)
    : days = j['days'] as int,
      hasData = j['analyticsState'] == 'READY',
      series = (j['series'] as List).map((v) => TrendDay.fromJson(v as Map<String, dynamic>)).toList(),
      previousActivity = (j['previous'] as List).map((v) => (v as Map)['activityMinutes'] as int?).toList(),
      recordedDays = (j['consistency'] as Map)['recordedDays'] as int,
      currentStreak = (j['consistency'] as Map)['currentStreak'] as int,
      activityTotal = (j['activity'] as Map)['totalMinutes'] as int?,
      activityPreviousTotal = (j['activity'] as Map)['previousTotalMinutes'] as int?,
      activityDays = (j['activity'] as Map)['activeDays'] as int,
      bestActivityMinutes = ((j['activity'] as Map)['bestDay'] as Map?)?['minutes'] as int?,
      glucoseReadings = (j['glucose'] as Map)['readings'] as int,
      glucoseDays = (j['glucose'] as Map)['daysWithReadings'] as int,
      notes = (j['notes'] as List).map((v) => TrendNote.fromJson(v as Map<String, dynamic>)).whereType<TrendNote>().where((n) => n is! UnknownNote).toList();

  final int days, recordedDays, currentStreak, activityDays, glucoseReadings, glucoseDays;
  final bool hasData;
  final List<TrendDay> series;
  final List<int?> previousActivity;
  final int? activityTotal, activityPreviousTotal, bestActivityMinutes;
  final List<TrendNote> notes;

  int get mealDays => series.where((d) => d.mealCount > 0).length;
  int get medTakenTotal => series.fold(0, (s, d) => s + d.medTaken);
  int get medSkippedTotal => series.fold(0, (s, d) => s + d.medSkipped);
  int get medConfirmed => medTakenTotal + medSkippedTotal;
}
