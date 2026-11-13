import '../../../core/network/api_client.dart';

class JourneyCapabilities {
  JourneyCapabilities.fromJson(Map<String, dynamic> j)
    : coaching = j['coaching'] == true,
      assistant = j['assistant'] == true,
      community = j['community'] == true,
      glucoseVisible = j['glucoseFeaturesVisible'] == true,
      medicationVisible = j['medicationFeaturesVisible'] == true,
      screeningReminder = j['screeningReminder'] == true;
  final bool coaching,
      assistant,
      community,
      glucoseVisible,
      medicationVisible,
      screeningReminder;
}

class JourneyView {
  JourneyView.fromJson(Map<String, dynamic> j)
    : journey = j['journey'] as String,
      label = (j['label'] as String?) ?? '',
      description = (j['description'] as String?) ?? '',
      source = (j['source'] as String?) ?? '',
      assumed = j['assumed'] == true,
      capabilities = JourneyCapabilities.fromJson(
        (j['capabilities'] as Map<String, dynamic>?) ?? const {},
      );
  final String journey, label, description, source;
  final bool assumed;
  final JourneyCapabilities capabilities;
  bool get loggingOnly => journey == 'UNDETERMINED';
}

class JourneyRepository {
  JourneyRepository(this._api);
  final ApiClient _api;

  Future<JourneyView> get() async =>
      JourneyView.fromJson((await _api.get('/api/me/journey')).object);
}
