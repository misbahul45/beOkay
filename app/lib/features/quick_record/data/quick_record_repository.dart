import '../../../core/network/api_client.dart';

class QuickMeal {
  QuickMeal.fromJson(Map<String, dynamic> j)
    : key = j['key'] as String,
      title = j['title'] as String,
      category = j['category'] as String,
      count = j['count'] as int,
      lastAt = DateTime.parse(j['lastAt'] as String),
      nutritionKnown = j['nutritionKnown'] == true,
      template = (j['template'] as Map).cast<String, dynamic>();
  final String key, title, category;
  final int count;
  final DateTime lastAt;
  final bool nutritionKnown;
  final Map<String, dynamic> template;
}

class QuickActivity {
  QuickActivity.fromJson(Map<String, dynamic> j)
    : key = j['key'] as String,
      title = j['title'] as String,
      count = j['count'] as int,
      lastAt = DateTime.parse(j['lastAt'] as String),
      template = (j['template'] as Map).cast<String, dynamic>();
  final String key, title;
  final int count;
  final DateTime lastAt;
  final Map<String, dynamic> template;
  int get minutes => (template['durationMinutes'] as num).toInt();
}

class QuickSuggestions {
  QuickSuggestions.fromJson(Map<String, dynamic> j)
    : meals = [
        for (final m in (j['meals'] as List? ?? const []))
          QuickMeal.fromJson(m as Map<String, dynamic>),
      ],
      activities = [
        for (final a in (j['activities'] as List? ?? const []))
          QuickActivity.fromJson(a as Map<String, dynamic>),
      ];
  final List<QuickMeal> meals;
  final List<QuickActivity> activities;
  bool get isEmpty => meals.isEmpty && activities.isEmpty;
}

class QuickRecordRepository {
  QuickRecordRepository(this._api);
  final ApiClient _api;
  Future<QuickSuggestions> suggestions() async => QuickSuggestions.fromJson(
    (await _api.get('/api/me/quick-record/suggestions')).object,
  );
}
