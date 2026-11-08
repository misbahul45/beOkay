import '../../nutrition/data/nutrition_models.dart';
import '../../glucose/data/glucose_models.dart';

class TodayOverview {
  const TodayOverview({
    required this.date,
    required this.greeting,
    required this.timezone,
    required this.glucoseUnit,
    required this.generatedAt,
    this.nutrition,
    this.glucose,
    this.events = const [],
  });

  final String date;
  final String greeting;
  final String timezone;
  final String glucoseUnit;
  final DateTime generatedAt;
  final NutritionDay? nutrition;
  final GlucoseDay? glucose;
  final List<TodayEvent> events;

  factory TodayOverview.fromJson(Map<String, dynamic> json) => TodayOverview(
    date: json['date'] as String,
    greeting: json['greeting'] as String,
    timezone: json['timezone'] as String,
    glucoseUnit: json['glucoseUnit'] as String,
    generatedAt: DateTime.parse(json['generatedAt'] as String),
    nutrition: json['nutrition'] is Map<String, dynamic>
        ? NutritionDay.fromJson(json['nutrition'] as Map<String, dynamic>)
        : null,
    glucose: json['glucose'] is Map<String, dynamic>
        ? GlucoseDay.fromJson(json['glucose'] as Map<String, dynamic>)
        : null,
    events:
        ((json['timeline'] as Map<String, dynamic>?)?['items'] as List? ?? [])
            .map((v) => TodayEvent.fromJson(v as Map<String, dynamic>))
            .toList(),
  );
}

class TodayEvent {
  TodayEvent.fromJson(Map<String, dynamic> json)
    : domain = json['domain'] as String,
      recordId = json['recordId'] as String,
      localTime = json['localTime'] as String,
      category = json['category'] as String?,
      itemCount = json['itemCount'] as int?,
      displayValue = json['displayValue'] as num?,
      displayUnit = json['displayUnit'] as String?,
      qualityStatus = json['qualityStatus'] as String?;
  final String domain, recordId, localTime;
  final String? category, displayUnit, qualityStatus;
  final int? itemCount;
  final num? displayValue;
}
