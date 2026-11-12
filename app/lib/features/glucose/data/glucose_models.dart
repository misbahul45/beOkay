const glucoseContexts = {
  'unknown': 'Tidak diketahui',
  'fasting': 'Puasa',
  'before_meal': 'Sebelum makan',
  'after_meal': 'Setelah makan',
  'bedtime': 'Sebelum tidur',
  'other': 'Lainnya',
};

String? validateGlucoseInput(String? text, String unit) {
  final input = (text ?? '').trim().replaceAll(',', '.');
  final value = double.tryParse(input);
  final canonical = value == null
      ? null
      : value * (unit == 'mmol/L' ? 18.016 : 1);
  if (!RegExp(r'^\d+(\.\d{1,4})?$').hasMatch(input) ||
      value == null ||
      !value.isFinite ||
      canonical! < 1 ||
      canonical > 2000) {
    return 'Masukkan nilai valid dalam batas numerik aplikasi.';
  }
  return null;
}

const glucoseLowMgDl = 70;
const glucoseHighMgDl = 300;
const mgDlPerMmolL = 18.016;

class GlucoseAlert {
  const GlucoseAlert(this.level, this.title, this.message);
  GlucoseAlert.fromJson(Map<String, dynamic> j)
    : level = j['level'] as String,
      title = j['title'] as String,
      message = j['message'] as String;
  final String level, title, message;
  bool get low => level == 'LOW';
}

const _lowAlert = GlucoseAlert(
  'LOW',
  'Angka ini di bawah 70 mg/dL',
  'Bila kamu merasa gemetar, berkeringat, bingung, atau lemas, ikuti rencana penanganan gula rendah dari tenaga kesehatanmu. Bila tidak membaik, pingsan, atau sulit sadar, segera hubungi layanan darurat 119.',
);
const _highAlert = GlucoseAlert(
  'HIGH',
  'Angka ini 300 mg/dL atau lebih',
  'Periksa ulang dengan alat yang sama bila memungkinkan. Bila tetap tinggi, atau disertai muntah, sangat haus, sesak, atau lemas berat, segera hubungi tenaga kesehatan atau layanan darurat 119.',
);

GlucoseAlert? glucoseAlertFor(num? value, String unit) {
  if (value == null) return null;
  final mgdl = unit == 'mmol/L' ? value * mgDlPerMmolL : value;
  if (mgdl < glucoseLowMgDl) return _lowAlert;
  if (mgdl >= glucoseHighMgDl) return _highAlert;
  return null;
}

class GlucoseContext {
  GlucoseContext.fromJson(Map<String, dynamic> j)
    : line = j['line'] as String,
      comparison = (j['comparison'] as Map?)?['comparison'] as String?,
      previousValue = (j['previous'] as Map?)?['value'] as num?,
      previousStamp = j['previous'] is Map
          ? '${(j['previous'] as Map)['localDate']} · ${(j['previous'] as Map)['localTime']}'
          : null,
      displayUnit = j['displayUnit'] as String,
      note = (j['neutralNote'] as String?) ?? '';
  final String line, displayUnit, note;
  final String? comparison, previousStamp;
  final num? previousValue;
}

class GlucoseRecord {
  GlucoseRecord.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      originalValue = json['originalValue'] as num,
      originalUnit = json['originalUnit'] as String,
      displayValue = json['displayValue'] as num,
      displayUnit = json['displayUnit'] as String,
      valueMgDl = json['valueMgDl'] as num,
      measuredAt = DateTime.parse(json['measuredAt'] as String),
      localDate = json['localDate'] as String,
      localTime = json['localTime'] as String,
      timezone = json['timezone'] as String,
      version = json['version'] as int,
      mealContext = json['mealContext'] as String,
      qualityStatus = json['qualityStatus'] as String,
      notes = json['notes'] as String?,
      archived = json['archivedAt'] != null,
      recordedAt = json['recordedAt'] as String?,
      receivedAt = json['receivedAt'] as String?,
      alert = json['alert'] is Map
          ? GlucoseAlert.fromJson(json['alert'] as Map<String, dynamic>)
          : null;
  final GlucoseAlert? alert;
  final String id,
      originalUnit,
      displayUnit,
      localDate,
      localTime,
      timezone,
      mealContext,
      qualityStatus;
  final String? notes, recordedAt, receivedAt;
  final num originalValue, displayValue, valueMgDl;
  final DateTime measuredAt;
  final int version;
  final bool archived;
  String get label => '$displayValue $displayUnit';
  String get qualityLabel => qualityStatus == 'needs_review'
      ? 'Perlu ditinjau · ditandai pengguna'
      : 'Dilaporkan sendiri';
}

class GlucosePage {
  const GlucosePage(
    this.items,
    this.nextCursor,
    this.timezone,
    this.displayUnit,
  );
  final List<GlucoseRecord> items;
  final String? nextCursor;
  final String timezone, displayUnit;
  factory GlucosePage.fromJson(Map<String, dynamic> json) => GlucosePage(
    (json['items'] as List)
        .map((v) => GlucoseRecord.fromJson(v as Map<String, dynamic>))
        .toList(),
    json['nextCursor'] as String?,
    json['timezone'] as String,
    json['displayUnit'] as String,
  );
}

class GlucoseDay {
  GlucoseDay.fromJson(Map<String, dynamic> json)
    : count = json['count'] as int,
      reviewCount = json['reviewCount'] as int,
      eligibleCount = json['eligibleCount'] as int,
      latest = json['latest'] == null
          ? null
          : GlucoseRecord.fromJson(json['latest'] as Map<String, dynamic>),
      mean = json['mean'] as num?,
      minimum = json['minimum'] as num?,
      maximum = json['maximum'] as num?,
      displayUnit = json['displayUnit'] as String,
      computationVersion = json['computationVersion'] as String,
      computedAt = json['computedAt'] as String,
      analyticsState = json['analyticsState'] as String? ?? 'READY',
      freshness = json['freshness'] as String? ?? 'CURRENT';
  final String analyticsState, freshness;
  final int count, reviewCount, eligibleCount;
  final GlucoseRecord? latest;
  final num? mean, minimum, maximum;
  final String displayUnit, computationVersion, computedAt;
}
