const activityTypes = {
  'walking': 'Jalan kaki',
  'cycling': 'Bersepeda',
  'running': 'Lari',
  'strength': 'Latihan kekuatan',
  'other': 'Lainnya',
};
const activityIntensities = {
  'unknown': 'Tidak diketahui',
  'light': 'Ringan',
  'moderate': 'Sedang',
  'vigorous': 'Berat',
};
String? validateActivityDuration(String? input) {
  final text = (input ?? '').trim();
  final value = int.tryParse(text);
  return RegExp(r'^\d+$').hasMatch(text) &&
          value != null &&
          value >= 1 &&
          value <= 1440
      ? null
      : 'Isi durasi 1–1440 menit dalam bilangan bulat.';
}

String? validateActivityMetric(String? input, {required bool steps}) {
  final text = (input ?? '').trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  final value = num.tryParse(text);
  return RegExp(steps ? r'^\d+$' : r'^\d+(\.\d{1,3})?$').hasMatch(text) &&
          value != null &&
          value.isFinite &&
          value >= 0 &&
          value <= (steps ? 1000000 : 1000)
      ? null
      : steps
      ? 'Isi langkah 0–1000000 dalam bilangan bulat.'
      : 'Isi jarak 0–1000 km, maksimal 3 desimal.';
}

class ActivityRecord {
  ActivityRecord.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      activityType = j['activityType'] as String,
      startedAt = DateTime.parse(j['startedAt'] as String),
      endedAt = DateTime.parse(j['endedAt'] as String),
      durationMinutes = j['durationMinutes'] as int,
      distanceKm = j['distanceKm'] as num?,
      steps = j['steps'] as int?,
      reportedIntensity = j['reportedIntensity'] as String,
      qualityStatus = j['qualityStatus'] as String,
      notes = j['notes'] as String?,
      version = j['version'] as int,
      archived = j['archivedAt'] != null,
      localDate = j['localDate'] as String,
      localTime = j['localTime'] as String,
      endLocalDate = j['endLocalDate'] as String,
      endLocalTime = j['endLocalTime'] as String,
      timezone = j['timezone'] as String,
      recordedAt = j['recordedAt'] as String?,
      receivedAt = j['receivedAt'] as String?;
  final String id,
      activityType,
      reportedIntensity,
      qualityStatus,
      localDate,
      localTime,
      endLocalDate,
      endLocalTime,
      timezone;
  final String? notes, recordedAt, receivedAt;
  final DateTime startedAt, endedAt;
  final int durationMinutes, version;
  final int? steps;
  final num? distanceKm;
  final bool archived;
  String get qualityLabel => qualityStatus == 'needs_review'
      ? 'Perlu ditinjau · ditandai pengguna'
      : 'Dilaporkan sendiri';
}

class ActivityPage {
  ActivityPage.fromJson(Map<String, dynamic> j)
    : items = (j['items'] as List)
          .map((v) => ActivityRecord.fromJson(v as Map<String, dynamic>))
          .toList(),
      nextCursor = j['nextCursor'] as String?,
      timezone = j['timezone'] as String;
  final List<ActivityRecord> items;
  final String? nextCursor;
  final String timezone;
}

class ActivityMetric {
  ActivityMetric.fromJson(Map<String, dynamic> j)
    : value = j['value'] as num?,
      knownSessions = j['knownSessions'] as int,
      totalSessions = j['totalSessions'] as int,
      coverage = j['coverage'] as String;
  final num? value;
  final int knownSessions, totalSessions;
  final String coverage;
  String label(String unit) => value == null
      ? 'Belum diketahui'
      : '$value $unit${coverage == 'PARTIAL' ? ' · sebagian ($knownSessions/$totalSessions sesi)' : ''}';
}

class ActivityTotals {
  ActivityTotals.fromJson(Map<String, dynamic> j)
    : count = j['count'] as int,
      eligibleCount = j['eligibleCount'] as int,
      reviewCount = j['reviewCount'] as int,
      durationMinutes = j['durationMinutes'] as int?,
      distanceKm = ActivityMetric.fromJson(
        j['distanceKm'] as Map<String, dynamic>,
      ),
      steps = ActivityMetric.fromJson(j['steps'] as Map<String, dynamic>);
  final int count, eligibleCount, reviewCount;
  final int? durationMinutes;
  final ActivityMetric distanceKm, steps;
}

class ActivityDay extends ActivityTotals {
  ActivityDay.fromJson(super.j) : date = j['date'] as String, super.fromJson();
  final String date;
}

class ActivitySummary extends ActivityTotals {
  ActivitySummary.fromJson(super.j)
    : date = j['date'] as String,
      startDate = j['startDate'] as String,
      endDate = j['endDate'] as String,
      timezone = j['timezone'] as String,
      firstDay = j['firstDay'] as int?,
      activeDays = j['activeDays'] as int,
      computedAt = j['computedAt'] as String,
      computationVersion = j['computationVersion'] as String,
      days = (j['days'] as List)
          .map((v) => ActivityDay.fromJson(v as Map<String, dynamic>))
          .toList(),
      super.fromJson();
  final String date,
      startDate,
      endDate,
      timezone,
      computedAt,
      computationVersion;
  final int? firstDay;
  final int activeDays;
  final List<ActivityDay> days;
}
