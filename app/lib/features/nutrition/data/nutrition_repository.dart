import '../../../core/network/account_scoped_repository.dart';
import 'nutrition_models.dart';

class NutritionRepository extends AccountScopedRepository {
  NutritionRepository(super.api, {required super.isCurrentAccount});
  Future<MealPage> list({
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
    return MealPage.fromJson((await api.get('/api/me/meals?$query')).object);
  }

  Future<MealRecord> get(String id) async =>
      MealRecord.fromJson((await api.get('/api/me/meals/$id')).object);
  Future<MealRecord> save(Map<String, dynamic> body, {String? id}) async =>
      MealRecord.fromJson(
        (await write(
          id == null ? 'POST' : 'PATCH',
          id == null ? '/api/me/meals' : '/api/me/meals/$id',
          body,
        )).object,
      );
  Future<List<FoodReference>> search(String q) async =>
      ((await api.get(
                '/api/foods/search?q=${Uri.encodeQueryComponent(q)}',
              )).object['items']
              as List)
          .map((v) => FoodReference.fromJson(v as Map<String, dynamic>))
          .toList();
  Future<FoodReference> saveFood(
    Map<String, dynamic> body, {
    String? id,
  }) async => FoodReference.fromJson(
    (await write(
      id == null ? 'POST' : 'PATCH',
      id == null ? '/api/me/foods' : '/api/me/foods/$id',
      body,
    )).object,
  );
  Future<List<Map<String, dynamic>>> revisions(String id) async =>
      ((await api.get('/api/me/meals/$id/revisions')).object['items'] as List)
          .cast<Map<String, dynamic>>();
}
