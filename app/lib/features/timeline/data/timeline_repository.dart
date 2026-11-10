import '../../../core/network/api_client.dart';
import 'timeline_models.dart';

class TimelineRepository {
  const TimelineRepository(this.api);
  final ApiClient api;

  Future<TimelinePage> list({
    String domain = 'all',
    String? date,
    String? cursor,
    bool archived = false,
    int limit = 20,
  }) async {
    final query = <String, String>{
      'domain': domain,
      'limit': '$limit',
      'archived': '$archived',
      'date': ?date,
      'cursor': ?cursor,
    };
    final path = Uri(
      path: '/api/me/timeline',
      queryParameters: query,
    ).toString();
    return TimelinePage.fromJson((await api.get(path)).object);
  }
}
