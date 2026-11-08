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
      receivedAt = json['receivedAt'] as String?;
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
      computedAt = json['computedAt'] as String;
  final int count, reviewCount, eligibleCount;
  final GlucoseRecord? latest;
  final num? mean, minimum, maximum;
  final String displayUnit, computationVersion, computedAt;
}
