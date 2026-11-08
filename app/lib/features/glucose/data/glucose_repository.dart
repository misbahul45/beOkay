import '../../../core/network/account_scoped_repository.dart';
import 'glucose_models.dart';

class GlucoseRepository extends AccountScopedRepository {
  GlucoseRepository(super.api, {required super.isCurrentAccount});
  Future<GlucoseRecord> get(String id) async =>
      GlucoseRecord.fromJson((await api.get('/api/me/glucose/$id')).object);
  Future<GlucoseRecord> save(Map<String, dynamic> body, {String? id}) async =>
      GlucoseRecord.fromJson(
        (await write(
          id == null ? 'POST' : 'PATCH',
          id == null ? '/api/me/glucose' : '/api/me/glucose/$id',
          body,
        )).object,
      );
  Future<GlucosePage> list({
    String? cursor,
    String? date,
    bool archived = false,
  }) async {
    final query = Uri(
      queryParameters: {
        'cursor': ?cursor,
        'date': ?date,
        'archived': '$archived',
      },
    ).query;
    return GlucosePage.fromJson(
      (await api.get('/api/me/glucose?$query')).object,
    );
  }

  Future<GlucoseDay> daily({String? date}) async => GlucoseDay.fromJson(
    (await api.get(
      '/api/me/glucose/summary${date == null ? '' : '?date=$date'}',
    )).object,
  );
  Future<List<Map<String, dynamic>>> revisions(String id) async =>
      ((await api.get('/api/me/glucose/$id/revisions')).object['items'] as List)
          .cast<Map<String, dynamic>>();
}
