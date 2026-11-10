import '../../../core/network/api_client.dart';
import 'health_models.dart';

class HealthRepository {
  HealthRepository(this._api);

  final ApiClient _api;

  Future<HealthProfile> get() async =>
      HealthProfile.fromJson((await _api.get('/api/me/health-profile')).object);

  Future<HealthProfile> save({
    required DiagnosisStatus status,
    required DiabetesType? type,
    required int? year,
    required List<Treatment> treatments,
  }) async {
    final body = {
      'diagnosisStatus': status.wire,
      'diabetesType': status == DiagnosisStatus.diagnosed ? type?.wire : null,
      'diagnosedYear': status == DiagnosisStatus.diagnosed ? year : null,
      'treatmentContext': treatments.map((item) => item.wire).toList(),
    };
    return HealthProfile.fromJson(
      (await _api.put('/api/me/health-profile', body: body)).object,
    );
  }
}
