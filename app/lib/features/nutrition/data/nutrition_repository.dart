import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/token_storage.dart';
import 'nutrition_models.dart';

class NutritionRepository {
  NutritionRepository(this.api, {required this.isCurrentAccount});
  final ApiClient api;
  final bool Function() isCurrentAccount;
  Future<ApiResponse> write(
    String method,
    String path,
    Map<String, dynamic> body,
  ) async {
    final token = await api.tokens.read();
    if (token == null || !isCurrentAccount()) {
      throw const ApiException(
        status: 401,
        code: 'ACCOUNT_CHANGED',
        message: 'Akun berubah. Buka kembali formulir.',
      );
    }
    final captured = MemoryTokenStorage();
    await captured.write(token);
    final client = ApiClient(
      client: api.client,
      tokens: captured,
      baseUrl: api.baseUrl,
      onUnauthorized: () {
        if (isCurrentAccount()) api.onUnauthorized?.call();
      },
    );
    return client.send(method, path, body: body);
  }

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
