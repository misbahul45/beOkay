import '../../../core/network/api_client.dart';
import 'consent_models.dart';

class ConsentRepository {
  ConsentRepository(this._api);

  final ApiClient _api;

  Future<ConsentPolicy> currentPolicy() async => ConsentPolicy.fromJson(
    (await _api.get(
      '/api/consent-policies/current',
      authenticated: false,
    )).object,
  );

  Future<ConsentOverview> overview() async =>
      ConsentOverview.fromJson((await _api.get('/api/me/consents')).object);

  Future<ConsentOverview> grant({
    required String policyVersion,
    required List<String> purposes,
    required String source,
  }) async {
    final response = await _api.post(
      '/api/me/consents',
      body: {
        'policyVersion': policyVersion,
        'purposes': purposes,
        'source': source,
      },
    );
    return ConsentOverview.fromJson(response.object);
  }

  Future<ConsentOverview> withdraw(List<String> purposes) async {
    final response = await _api.post(
      '/api/me/consents/withdraw',
      body: {'purposes': purposes},
    );
    return ConsentOverview.fromJson(response.object);
  }
}
