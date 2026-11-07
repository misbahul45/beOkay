import '../../../core/network/api_client.dart';
import 'onboarding_status.dart';

class OnboardingRepository {
  OnboardingRepository(this._api);

  final ApiClient _api;

  Future<OnboardingStatus> get() async => OnboardingStatus.fromJson((await _api.get('/api/me/onboarding')).object);

  Future<OnboardingStatus> markIntroSeen(int expectedVersion) async {
    final response = await _api.patch('/api/me/onboarding', body: {'introSeen': true, 'expectedVersion': expectedVersion});
    return OnboardingStatus.fromJson(response.object);
  }

  Future<OnboardingStatus> complete() async => OnboardingStatus.fromJson((await _api.post('/api/me/onboarding/complete')).object);
}
