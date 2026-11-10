import '../../../core/network/api_client.dart';
import 'contextual_insights.dart';
import 'daily_insights.dart';
import 'trends.dart';
import 'weekly_insights.dart';

class InsightsRepository {
  const InsightsRepository(this.api);
  final ApiClient api;

  Future<DailyInsights> daily({String? date}) async {
    final path = Uri(
      path: '/api/me/summaries/daily',
      queryParameters: {'date': ?date},
    ).toString();
    return DailyInsights.fromJson((await api.get(path)).object);
  }

  Future<WeeklyInsights> weekly({String? date}) async {
    final path = Uri(
      path: '/api/me/summaries/weekly',
      queryParameters: {'date': ?date},
    ).toString();
    return WeeklyInsights.fromJson((await api.get(path)).object);
  }

  Future<ContextualInsights> contextual() async => ContextualInsights.fromJson(
    (await api.get('/api/me/insights/contextual')).object,
  );

  Future<Trends> trends({required int days}) async =>
      Trends.fromJson((await api.get('/api/me/trends?days=$days')).object);
}
