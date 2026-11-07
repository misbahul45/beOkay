import '../../../core/network/api_client.dart';
import 'preferences_models.dart';

class PreferencesRepository {
  PreferencesRepository(this._api);

  final ApiClient _api;

  Future<Preferences> get() async => Preferences.fromJson((await _api.get('/api/me/preferences')).object);

  Future<Preferences> update({
    String? timezone,
    GlucoseUnit? glucoseUnit,
    TextSizePreference? textSize,
    bool? reduceMotion,
  }) async {
    final body = <String, dynamic>{
      'timezone': ?timezone,
      'glucoseUnit': ?glucoseUnit?.wire,
      'textSize': ?textSize?.wire,
      'reduceMotion': ?reduceMotion,
    };
    return Preferences.fromJson((await _api.patch('/api/me/preferences', body: body)).object);
  }
}
