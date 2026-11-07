import '../../../core/network/api_client.dart';
import 'today_overview.dart';

class TodayRepository {
  const TodayRepository(this.api);
  final ApiClient api;

  Future<TodayOverview> get() async =>
      TodayOverview.fromJson((await api.get('/api/me/today')).object);
}
