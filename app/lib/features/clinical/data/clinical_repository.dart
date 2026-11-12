import '../../../core/network/account_scoped_repository.dart';
import 'clinical_models.dart';

class ClinicalRepository extends AccountScopedRepository {
  ClinicalRepository(
    super.api, {
    required super.isCurrentAccount,
    super.enqueueOffline,
  });

  Future<ClinicalSummary> summary() async => ClinicalSummary.fromJson(
    (await api.get('/api/me/clinical/summary')).object,
  );

  Future<List<VitalRecord>> vitals({String? kind}) async => [
    for (final v
        in ((await api.get(
              '/api/me/vitals?limit=50${kind == null ? '' : '&kind=$kind'}',
            )).object['items']
            as List))
      VitalRecord.fromJson(v as Map<String, dynamic>),
  ];

  Future<List<LabRecord>> labs({String? test}) async => [
    for (final v
        in ((await api.get(
              '/api/me/labs?limit=50${test == null ? '' : '&test=$test'}',
            )).object['items']
            as List))
      LabRecord.fromJson(v as Map<String, dynamic>),
  ];

  Future<VitalRecord> saveVital(
    Map<String, dynamic> body, {
    String? id,
  }) async => VitalRecord.fromJson(
    (await write(
      id == null ? 'POST' : 'PATCH',
      id == null ? '/api/me/vitals' : '/api/me/vitals/$id',
      body,
      queue: (
        domain: 'vital',
        recordId: id ?? body['id'] as String,
        parentId: null,
      ),
    )).object,
  );

  Future<LabRecord> saveLab(Map<String, dynamic> body, {String? id}) async =>
      LabRecord.fromJson(
        (await write(
          id == null ? 'POST' : 'PATCH',
          id == null ? '/api/me/labs' : '/api/me/labs/$id',
          body,
          queue: (
            domain: 'lab',
            recordId: id ?? body['id'] as String,
            parentId: null,
          ),
        )).object,
      );
}
