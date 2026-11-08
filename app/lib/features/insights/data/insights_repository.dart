import '../../../core/network/api_client.dart';
import 'daily_insights.dart';

class InsightsRepository {
  const InsightsRepository(this.api);
  final ApiClient api;

  Future<DailyInsights> daily({String? date}) async {
    final path = Uri(path: '/api/me/summaries/daily', queryParameters: {'date': ?date}).toString();
    return DailyInsights.fromJson((await api.get(path)).object);
  }
}
