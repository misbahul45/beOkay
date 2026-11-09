import '../../../core/network/account_scoped_repository.dart';

class Occurrence {
  Occurrence.fromJson(Map<String, dynamic> j)
    : regimenId = j['regimenId'] as String,
      scheduleId = j['scheduleId'] as String,
      name = j['name'] as String,
      strength = j['strength'] as String?,
      localTime = j['localTime'] as String,
      scheduledAt = j['scheduledAt'] as String,
      status = j['status'] as String,
      intakeId = j['intakeId'] as String?,
      intakeVersion = j['intakeVersion'] as int?;
  final int? intakeVersion;
  final String regimenId, scheduleId, name, localTime, scheduledAt, status;
  final String? strength, intakeId;
}

class MedicationToday {
  MedicationToday.fromJson(Map<String, dynamic> j)
    : date = j['date'] as String,
      scheduled = j['scheduled'] as int,
      taken = j['taken'] as int,
      skipped = j['skipped'] as int,
      unknown = j['unknown'] as int,
      items = (j['items'] as List).map((v) => Occurrence.fromJson(v as Map<String, dynamic>)).toList();
  final String date;
  final int scheduled, taken, skipped, unknown;
  final List<Occurrence> items;
}

class Regimen {
  Regimen.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      strength = j['strength'] as String?,
      dosageForm = j['dosageForm'] as String?,
      instructions = j['dosingInstructions'] as String?,
      status = j['status'] as String,
      version = j['version'] as int,
      schedules = ((j['schedules'] as List?) ?? const []).cast<Map<String, dynamic>>();
  final String id, name, status;
  final String? strength, dosageForm, instructions;
  final int version;
  final List<Map<String, dynamic>> schedules;

  String get subtitle => [?strength, ?dosageForm].join(' · ');
  String get scheduleLabel => schedules.isEmpty ? 'Belum ada jadwal' : schedules.map((s) => s['localTime']).join(', ');
}

class IntakeRecord {
  IntakeRecord.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      status = j['status'] as String,
      eventAt = DateTime.parse(j['eventAt'] as String),
      version = j['version'] as int,
      archived = j['archivedAt'] != null;
  final String id, status;
  final DateTime eventAt;
  final int version;
  final bool archived;
}

class MedicationRepository extends AccountScopedRepository {
  MedicationRepository(super.api, {required super.isCurrentAccount, super.enqueueOffline});

  Future<List<Regimen>> list() async => ((await api.get('/api/me/medications?limit=50')).object['items'] as List).map((v) => Regimen.fromJson(v as Map<String, dynamic>)).toList();
  Future<MedicationToday> today() async => MedicationToday.fromJson((await api.get('/api/me/medications/today')).object);
  Future<void> createRegimen(Map<String, dynamic> body) async => write('POST', '/api/me/medications', body);
  Future<void> updateRegimen(String id, Map<String, dynamic> body) async => write('PATCH', '/api/me/medications/$id', body);
  Future<void> createSchedule(String regimenId, Map<String, dynamic> body) async => write('POST', '/api/me/medications/$regimenId/schedules', body);
  Future<void> updateIntake(String regimenId, String id, Map<String, dynamic> body) async => write('PATCH', '/api/me/medications/$regimenId/intakes/$id', body);
  Future<void> createIntake(String regimenId, Map<String, dynamic> body) async => write('POST', '/api/me/medications/$regimenId/intakes', body, queue: (domain: 'medication_intake', recordId: body['id'] as String, parentId: regimenId));
  Future<List<IntakeRecord>> intakes(String regimenId) async =>
      ((await api.get('/api/me/medications/$regimenId/intakes?limit=50&archived=false')).object['items'] as List).map((v) => IntakeRecord.fromJson(v as Map<String, dynamic>)).toList();
}
