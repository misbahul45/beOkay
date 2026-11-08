import '../../nutrition/data/nutrition_models.dart';

class TodayOverview {
  const TodayOverview({
    required this.date,
    required this.greeting,
    required this.timezone,
    required this.glucoseUnit,
    required this.generatedAt,
    this.nutrition,
  });

  final String date;
  final String greeting;
  final String timezone;
  final String glucoseUnit;
  final DateTime generatedAt;
  final NutritionDay? nutrition;

  factory TodayOverview.fromJson(Map<String, dynamic> json) => TodayOverview(
    date: json['date'] as String,
    greeting: json['greeting'] as String,
    timezone: json['timezone'] as String,
    glucoseUnit: json['glucoseUnit'] as String,
    generatedAt: DateTime.parse(json['generatedAt'] as String),
    nutrition: json['nutrition'] is Map<String, dynamic>
        ? NutritionDay.fromJson(json['nutrition'] as Map<String, dynamic>)
        : null,
  );
}
