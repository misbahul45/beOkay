import '../../../core/network/api_client.dart';
import 'profile_models.dart';

class ProfileRepository {
  ProfileRepository(this._api);

  final ApiClient _api;

  Future<Profile> get() async => Profile.fromJson((await _api.get('/api/me/profile')).object);

  Future<Profile> update({String? displayName, int? birthYear, bool clearBirthYear = false}) async {
    final body = <String, dynamic>{};
    if (displayName != null) body['displayName'] = displayName;
    if (clearBirthYear) {
      body['birthYear'] = null;
    } else if (birthYear != null) {
      body['birthYear'] = birthYear;
    }
    return Profile.fromJson((await _api.patch('/api/me/profile', body: body)).object);
  }
}
