import '../../activity/data/activity_models.dart';
import '../../glucose/data/glucose_models.dart';
import '../../nutrition/data/nutrition_models.dart';

/// Descriptive summary for one local day. Every value is derived from the
/// user's own records; nothing here is a prediction or a clinical interpretation.
class DailyInsights {
  DailyInsights.fromJson(Map<String, dynamic> json)
    : date = json['date'] as String,
      timezone = json['timezone'] as String,
      nutrition = NutritionDay.fromJson(json),
      nutritionFreshness = json['freshness'] as String? ?? 'CURRENT',
      nutritionComputedAt = json['computedAt'] as String?,
      glucose = GlucoseDay.fromJson(json['glucose'] as Map<String, dynamic>),
      activity = ActivitySummary.fromJson(json['activity'] as Map<String, dynamic>);

  final String date, timezone, nutritionFreshness;
  final String? nutritionComputedAt;
  final NutritionDay nutrition;
  final GlucoseDay glucose;
  final ActivitySummary activity;

  bool get isEmpty => nutrition.mealCount == 0 && glucose.count == 0 && activity.count == 0;
}
