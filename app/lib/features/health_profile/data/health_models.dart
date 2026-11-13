enum DiagnosisStatus {
  diagnosed(
    'diagnosed',
    'Sudah terdiagnosis',
    'Tenaga kesehatan pernah menyampaikan diagnosis diabetes.',
  ),
  notDiagnosed(
    'not_diagnosed',
    'Belum terdiagnosis',
    'Belum pernah mendapat diagnosis diabetes.',
  ),
  unknown('unknown', 'Belum yakin', 'Aku tidak tahu pasti statusnya.'),
  undisclosed(
    'undisclosed',
    'Tidak ingin menjawab',
    'Aku memilih tidak mengisi bagian ini.',
  );

  const DiagnosisStatus(this.wire, this.label, this.description);
  final String wire;
  final String label;
  final String description;

  static DiagnosisStatus? parse(String? value) {
    for (final item in DiagnosisStatus.values) {
      if (item.wire == value) return item;
    }
    return null;
  }
}

enum DiabetesType {
  type2('type_2', 'Tipe 2'),
  type1('type_1', 'Tipe 1'),
  other('other', 'Jenis lain'),
  unknown('unknown', 'Belum yakin');

  const DiabetesType(this.wire, this.label);
  final String wire;
  final String label;

  static DiabetesType? parse(String? value) {
    for (final item in DiabetesType.values) {
      if (item.wire == value) return item;
    }
    return null;
  }
}

enum Treatment {
  oral('oral_medication', 'Obat minum'),
  insulin('insulin', 'Insulin'),
  lifestyle('lifestyle', 'Atur pola hidup'),
  none('none', 'Tidak ada pengobatan'),
  undisclosed('undisclosed', 'Tidak ingin menjawab');

  const Treatment(this.wire, this.label);
  final String wire;
  final String label;

  bool get isExclusive =>
      this == Treatment.none || this == Treatment.undisclosed;

  static Treatment? parse(String value) {
    for (final item in Treatment.values) {
      if (item.wire == value) return item;
    }
    return null;
  }
}

enum RiskStatement {
  prediabetes('prediabetes_told', 'Saya prediabetes', 'Dari hasil pemeriksaan'),
  atRisk(
    'at_risk_told',
    'Saya berisiko diabetes',
    'Misalnya karena riwayat keluarga',
  ),
  none('none', 'Tidak pernah', null),
  undisclosed('undisclosed', 'Tidak ingin menjawab', null);

  const RiskStatement(this.wire, this.label, this.description);
  final String wire;
  final String label;
  final String? description;

  static RiskStatement? parse(String? value) {
    for (final item in RiskStatement.values) {
      if (item.wire == value) return item;
    }
    return null;
  }
}

class JourneyInfo {
  const JourneyInfo({required this.value, required this.label});

  final String? value;
  final String? label;

  factory JourneyInfo.fromJson(Map<String, dynamic>? json) => JourneyInfo(
    value: json?['value'] as String?,
    label: json?['label'] as String?,
  );
}

class HealthProfile {
  const HealthProfile({
    required this.exists,
    required this.diagnosisStatus,
    required this.diabetesType,
    required this.diagnosedYear,
    required this.treatments,
    this.riskStatement,
    this.journey = const JourneyInfo(value: null, label: null),
  });

  final bool exists;
  final DiagnosisStatus? diagnosisStatus;
  final DiabetesType? diabetesType;
  final int? diagnosedYear;
  final List<Treatment> treatments;
  final RiskStatement? riskStatement;
  final JourneyInfo journey;

  factory HealthProfile.fromJson(Map<String, dynamic> json) => HealthProfile(
    exists: json['exists'] as bool,
    diagnosisStatus: DiagnosisStatus.parse(json['diagnosisStatus'] as String?),
    diabetesType: DiabetesType.parse(json['diabetesType'] as String?),
    diagnosedYear: json['diagnosedYear'] as int?,
    treatments: (json['treatmentContext'] as List<dynamic>)
        .map((item) => Treatment.parse(item as String))
        .whereType<Treatment>()
        .toList(),
    riskStatement: RiskStatement.parse(json['riskStatement'] as String?),
    journey: JourneyInfo.fromJson(json['journey'] as Map<String, dynamic>?),
  );
}
