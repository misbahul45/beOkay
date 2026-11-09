import '../../../core/network/account_scoped_repository.dart';
import 'activity_models.dart';

class ActivityRepository extends AccountScopedRepository {
  ActivityRepository(super.api, {required super.isCurrentAccount, super.enqueueOffline});
  Future<ActivityRecord> get(String id) async =>
      ActivityRecord.fromJson((await api.get('/api/me/activities/$id')).object);
  Future<ActivityRecord> save(Map<String, dynamic> body, {String? id}) async =>
      ActivityRecord.fromJson(
        (await write(
          id == null ? 'POST' : 'PATCH',
          id == null ? '/api/me/activities' : '/api/me/activities/$id',
          body,
          queue: id == null ? (domain: 'activity', recordId: body['id'] as String, parentId: null) : null,
        )).object,
      );
  Future<ActivityPage> list({
    String? cursor,
    String? date,
    bool archived = false,
  }) async {
    final q = Uri(
      queryParameters: {
        'cursor': ?cursor,
        'date': ?date,
        'archived': '$archived',
      },
    ).query;
    return ActivityPage.fromJson(
      (await api.get('/api/me/activities?$q')).object,
    );
  }

  Future<ActivitySummary> summary({
    String? date,
    bool weekly = false,
  }) async => ActivitySummary.fromJson(
    (await api.get(
      '/api/me/activities/${weekly ? 'weekly' : 'summary'}${date == null ? '' : '?date=$date'}',
    )).object,
  );
  Future<List<Map<String, dynamic>>> revisions(String id) async =>
      ((await api.get('/api/me/activities/$id/revisions')).object['items']
              as List)
          .cast<Map<String, dynamic>>();
}
