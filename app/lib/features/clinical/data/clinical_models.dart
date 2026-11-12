const vitalKinds = {
  'weight': ('Berat badan', 'kg'),
  'height': ('Tinggi badan', 'cm'),
  'waist': ('Lingkar pinggang', 'cm'),
  'blood_pressure': ('Tekanan darah', 'mmHg'),
};

const labTests = {
  'hba1c': ('HbA1c', ['%', 'mmol/mol']),
  'fasting_glucose': ('Glukosa puasa (lab)', ['mg/dL', 'mmol/L']),
  'ldl': ('Kolesterol LDL', ['mg/dL', 'mmol/L']),
  'hdl': ('Kolesterol HDL', ['mg/dL', 'mmol/L']),
  'total_cholesterol': ('Kolesterol total', ['mg/dL', 'mmol/L']),
  'triglycerides': ('Trigliserida', ['mg/dL', 'mmol/L']),
  'creatinine': ('Kreatinin', ['mg/dL', 'umol/L']),
  'egfr': ('eGFR', ['mL/min/1.73m2']),
  'urine_acr': ('Rasio albumin-kreatinin urin', ['mg/g', 'mg/mmol']),
};

String fmtNum(num v) {
  final d = v.toDouble();
  if (d == d.roundToDouble()) return d.toInt().toString();
  return d
      .toStringAsFixed(d * 10 == (d * 10).roundToDouble() ? 1 : 2)
      .replaceAll('.', ',');
}

class VitalRecord {
  VitalRecord.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      kind = j['kind'] as String,
      label = j['label'] as String,
      value = j['value'] as num,
      value2 = j['value2'] as num?,
      unit = j['unit'] as String,
      measuredAt = DateTime.parse(j['measuredAt'] as String),
      localDate = j['localDate'] as String,
      localTime = j['localTime'] as String,
      notes = j['notes'] as String?,
      version = j['version'] as int,
      archived = j['archivedAt'] != null;
  final String id, kind, label, unit, localDate, localTime;
  final num value;
  final num? value2;
  final DateTime measuredAt;
  final String? notes;
  final int version;
  final bool archived;
  String get display => kind == 'blood_pressure'
      ? '${fmtNum(value)}/${fmtNum(value2 ?? 0)} $unit'
      : '${fmtNum(value)} $unit';
}

class LabRecord {
  LabRecord.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      test = j['test'] as String,
      label = j['label'] as String,
      value = j['value'] as num,
      unit = j['unit'] as String,
      sampledAt = j['sampledAt'] as String,
      labName = j['labName'] as String?,
      source = j['source'] as String,
      notes = j['notes'] as String?,
      version = j['version'] as int,
      archived = j['archivedAt'] != null;
  final String id, test, label, unit, sampledAt, source;
  final num value;
  final String? labName, notes;
  final int version;
  final bool archived;
  String get display => '${fmtNum(value)} $unit';
}

class Change {
  Change.fromJson(Map<String, dynamic> j)
    : difference = j['difference'] as num,
      direction = j['direction'] as String;
  final num difference;
  final String direction;
  String text(String unit) => direction == 'SAME'
      ? 'Sama dengan sebelumnya'
      : '${direction == 'UP' ? 'Naik' : 'Turun'} ${fmtNum(difference.abs())} $unit dari sebelumnya';
}

class VitalSummary {
  VitalSummary.fromJson(Map<String, dynamic> j)
    : kind = j['kind'] as String,
      label = j['label'] as String,
      latest = j['latest'] is Map
          ? VitalRecord.fromJson(j['latest'] as Map<String, dynamic>)
          : null,
      change = j['change'] is Map
          ? Change.fromJson(j['change'] as Map<String, dynamic>)
          : null;
  final String kind, label;
  final VitalRecord? latest;
  final Change? change;
}

class LabSummary {
  LabSummary.fromJson(Map<String, dynamic> j)
    : test = j['test'] as String,
      label = j['label'] as String,
      latest = j['latest'] is Map
          ? LabRecord.fromJson(j['latest'] as Map<String, dynamic>)
          : null,
      change = j['change'] is Map
          ? Change.fromJson(j['change'] as Map<String, dynamic>)
          : null;
  final String test, label;
  final LabRecord? latest;
  final Change? change;
}

class Hba1cStatus {
  Hba1cStatus.fromJson(Map<String, dynamic> j)
    : status = j['status'] as String,
      lastSampledAt = j['lastSampledAt'] as String?,
      dueOn = j['dueOn'] as String?,
      daysSince = j['daysSince'] as int?;
  final String status;
  final String? lastSampledAt, dueOn;
  final int? daysSince;
  bool get due => status == 'DUE';
}

class ClinicalSummary {
  ClinicalSummary.fromJson(Map<String, dynamic> j)
    : vitals = [
        for (final v in j['vitals'] as List)
          VitalSummary.fromJson(v as Map<String, dynamic>),
      ],
      labs = [
        for (final v in j['labs'] as List)
          LabSummary.fromJson(v as Map<String, dynamic>),
      ],
      hba1c = Hba1cStatus.fromJson(j['hba1c'] as Map<String, dynamic>),
      notice = (j['notice'] as String?) ?? '';
  final List<VitalSummary> vitals;
  final List<LabSummary> labs;
  final Hba1cStatus hba1c;
  final String notice;
}
