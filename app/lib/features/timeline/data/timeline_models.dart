import '../../activity/data/activity_models.dart';
import '../../glucose/data/glucose_models.dart';
import '../../nutrition/data/nutrition_models.dart';

/// One event of the unified timeline. A read model projected by the server from
/// the authoritative domain tables; it never replaces the source record.
class TimelineItem {
  TimelineItem.fromJson(Map<String, dynamic> json)
    : domain = json['domain'] as String,
      recordId = json['recordId'] as String,
      localDate = json['localDate'] as String? ?? '',
      localTime = json['localTime'] as String,
      category = json['category'] as String?,
      itemCount = json['itemCount'] as int?,
      displayValue = json['displayValue'] as num?,
      displayUnit = json['displayUnit'] as String?,
      qualityStatus = json['qualityStatus'] as String?,
      mealContext = json['mealContext'] as String?,
      activityType = json['activityType'] as String?,
      durationMinutes = json['durationMinutes'] as int?,
      status = json['status'] as String?,
      medicationName = json['medicationName'] as String?,
      goalTitle = json['goalTitle'] as String?;

  final String domain, recordId, localDate, localTime;
  final String? category,
      displayUnit,
      qualityStatus,
      mealContext,
      activityType,
      status,
      medicationName,
      goalTitle;
  final int? itemCount, durationMinutes;
  final num? displayValue;

  bool get needsReview => qualityStatus == 'needs_review';

  String get title => switch (domain) {
    'meal' => mealCategories[category] ?? 'Makanan',
    'activity' => activityTypes[activityType] ?? 'Aktivitas',
    'medication' => medicationName ?? 'Obat',
    'goal' => goalTitle ?? 'Tujuan',
    _ => '$displayValue $displayUnit',
  };

  /// Source and measurement context are always shown so a user can tell a
  /// self-reported value from anything else.
  String get subtitle {
    final parts = <String>[
      localTime,
      switch (domain) {
        'meal' => '$itemCount item',
        'activity' => '$durationMinutes menit · dilaporkan sendiri',
        'medication' => switch (status) {
          'taken' => 'sudah diminum',
          'skipped' => 'dilewati',
          _ => 'belum dikonfirmasi',
        },
        'goal' => switch (status) {
          'completed' => 'check-in selesai',
          'skipped' => 'check-in dilewati',
          _ => 'belum dikonfirmasi',
        },
        _ =>
          'glukometer manual${glucoseContexts[mealContext] == null ? '' : ' · ${glucoseContexts[mealContext]}'}',
      },
      if (needsReview) 'perlu ditinjau',
    ];
    return parts.join(' · ');
  }
}

class TimelinePage {
  TimelinePage.fromJson(Map<String, dynamic> json)
    : items = (json['items'] as List)
          .map((v) => TimelineItem.fromJson(v as Map<String, dynamic>))
          .toList(),
      nextCursor = json['nextCursor'] as String?,
      timezone = json['timezone'] as String,
      supportedDomains = (json['supportedDomains'] as List).cast<String>();

  final List<TimelineItem> items;
  final String? nextCursor;
  final String timezone;
  final List<String> supportedDomains;
}
