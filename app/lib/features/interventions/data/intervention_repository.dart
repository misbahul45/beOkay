import '../../../core/network/account_scoped_repository.dart';

/// Satu saran dalam aplikasi. Isi berasal dari daftar pesan tetap di server (bukan hasil model).
class Intervention {
  Intervention.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      trigger = j['trigger'] as String,
      title = (j['content'] as Map<String, dynamic>)['title'] as String,
      body = (j['content'] as Map<String, dynamic>)['body'] as String,
      action = (j['content'] as Map<String, dynamic>)['action'] as String;
  final String id, trigger, title, body, action;
}

class InterventionRepository extends AccountScopedRepository {
  InterventionRepository(super.api, {required super.isCurrentAccount});

  /// Server memutuskan apakah ada saran (jam tenang, jatah, jeda, dan persetujuan dicek di sana).
  Future<void> consider(String trigger) async {
    await write('POST', '/api/me/interventions/evaluate', {'trigger': trigger});
  }

  Future<List<Intervention>> open() async => [
    for (final v
        in (await api.get('/api/me/interventions')).object['items'] as List)
      Intervention.fromJson(v as Map<String, dynamic>),
  ];

  Future<void> respond(String id, String kind, {int? snoozeMinutes}) async {
    await write('POST', '/api/me/interventions/$id/response', {
      'kind': kind,
      'snoozeMinutes': ?snoozeMinutes,
    });
  }

  Future<void> pauseForHours(int hours) async {
    await write('PATCH', '/api/me/intervention-preferences', {
      'pauseForHours': hours,
    });
  }
}
