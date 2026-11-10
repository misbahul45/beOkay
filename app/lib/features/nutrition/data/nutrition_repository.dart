import '../../../core/network/account_scoped_repository.dart';
import '../../food_preferences/data/food_preferences_repository.dart';
import 'nutrition_models.dart';

class NutritionRepository extends AccountScopedRepository {
  NutritionRepository(
    super.api, {
    required super.isCurrentAccount,
    super.enqueueOffline,
  });
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
          queue: (
            domain: 'meal',
            recordId: id ?? body['id'] as String,
            parentId: null,
          ),
        )).object,
      );
  Future<List<FoodReference>> search(String q) async =>
      ((await api.get(
                '/api/foods/search?q=${Uri.encodeQueryComponent(q)}',
              )).object['items']
              as List)
          .map((v) => FoodReference.fromJson(v as Map<String, dynamic>))
          .toList();
  Future<List<PortionMeasure>> measures(String foodId) async =>
      ((await api.get('/api/me/foods/$foodId/measures')).object['items']
              as List)
          .map((v) => PortionMeasure.fromJson(v as Map<String, dynamic>))
          .toList();

  Future<PortionMeasure> addMeasure(
    String foodId, {
    required String label,
    required num grams,
    required String basis,
  }) async => PortionMeasure.fromJson(
    (await write('POST', '/api/me/foods/$foodId/measures', {
      'label': label,
      'grams': grams,
      'basis': basis,
    })).object,
  );

  /// Referensi TKPI di basis data sendiri (tidak ada pihak ketiga selain layanan embedding di server).
  Future<List<ReferenceFood>> searchReference(String q) async =>
      ((await api.get(
                '/api/me/foods/reference?q=${Uri.encodeQueryComponent(q)}',
              )).object['items']
              as List)
          .map((v) => ReferenceFood.fromJson(v as Map<String, dynamic>))
          .toList();

  /// Pengecekan alergi/preferensi berdasarkan nama. Berbasis nama saja; bukan jaminan keamanan.
  Future<PreferenceChecks> preferenceChecks(List<String> names) =>
      FoodPreferencesRepository(
        api,
        isCurrentAccount: isCurrentAccount,
      ).check(names);

  /// Hanya dipanggil atas permintaan pengguna: teks pencarian dikirim ke sumber pihak ketiga lewat server.
  Future<ExternalSearch> searchExternal(String q) async {
    final r =
        (await api.get(
              '/api/me/foods/discover?q=${Uri.encodeQueryComponent(q)}&external=true',
            )).object['external']
            as Map<String, dynamic>;
    return ExternalSearch(
      r['status'] as String,
      (r['items'] as List)
          .map((v) => FoodCandidate.fromJson(v as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Kode batang divalidasi di server; yang dikirim ke Open Food Facts hanyalah kode itu.
  Future<BarcodeLookup> barcode(String code) async {
    final r = (await api.get(
      '/api/me/foods/barcode/${Uri.encodeComponent(code)}',
    )).object;
    return BarcodeLookup(
      r['status'] as String,
      r['candidate'] is Map<String, dynamic>
          ? FoodCandidate.fromJson(r['candidate'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Foto dikirim ke layanan pembaca gambar via server dan tidak disimpan. Hanya dipanggil setelah pengguna menyetujui.
  Future<LabelScan> scanLabel(List<int> jpeg) async => LabelScan.fromJson(
    (await api.postBytes(
      '/api/me/foods/scan/label',
      jpeg,
      contentType: 'image/jpeg',
    )).object,
  );

  /// Memanaskan model di server sebelum foto dikirim. Tanpa isi, hasil diabaikan, dan tidak pernah menggagalkan alur foto.
  Future<void> warmUpModel() async {
    try {
      await api.post('/api/me/ml/warmup', body: const <String, dynamic>{});
    } catch (_) {}
  }

  Future<PhotoScan> scanPhoto(List<int> jpeg) async => PhotoScan.fromJson(
    (await api.postBytes(
      '/api/me/foods/scan/photo',
      jpeg,
      contentType: 'image/jpeg',
    )).object,
  );

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
