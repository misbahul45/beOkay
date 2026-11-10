export '../../../core/ids/record_id.dart';

const mealCategories = {
  'breakfast': 'Sarapan',
  'lunch': 'Makan siang',
  'dinner': 'Makan malam',
  'snack': 'Camilan',
};
const portionUnits = {
  'g': 'g',
  'portion': 'porsi',
  'piece': 'buah / potong',
  'ml': 'mL',
};
const nutrientLabels = {
  'calories': 'Energi',
  'carbohydrates': 'Karbohidrat',
  'protein': 'Protein',
  'fat': 'Lemak',
  'fiber': 'Serat',
};

class NutritionDay {
  NutritionDay(this.mealCount, this.totals, this.recent);
  final int mealCount;
  final Map<String, NutrientTotal> totals;
  final List<RecentMeal> recent;
  factory NutritionDay.fromJson(Map<String, dynamic> json) => NutritionDay(
    json['mealCount'] as int,
    (json['totals'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, NutrientTotal.fromJson(v as Map<String, dynamic>)),
    ),
    (json['recent'] as List)
        .map((v) => RecentMeal.fromJson(v as Map<String, dynamic>))
        .toList(),
  );
}

class RecentMeal {
  RecentMeal(this.id, this.category, this.localTime, this.itemCount);
  final String id, category, localTime;
  final int itemCount;
  factory RecentMeal.fromJson(Map<String, dynamic> json) => RecentMeal(
    json['id'] as String,
    json['category'] as String,
    json['localTime'] as String,
    json['itemCount'] as int,
  );
}

class NutrientTotal {
  const NutrientTotal(
    this.value,
    this.coverage,
    this.knownItems,
    this.totalItems,
  );
  final num? value;
  final String coverage;
  final int knownItems, totalItems;
  factory NutrientTotal.fromJson(Map<String, dynamic> json) => NutrientTotal(
    json['value'] as num?,
    json['coverage'] as String,
    json['knownItems'] as int,
    json['totalItems'] as int,
  );
  String label(String unit) => value == null
      ? 'Belum tersedia'
      : '${value!.toStringAsFixed(1)} $unit${coverage == 'PARTIAL' ? ' · sebagian ($knownItems/$totalItems item)' : ''}';
}

class FoodReference {
  FoodReference(this.id, this.name, this.source, this.status, this.per100g);
  final String id, name, source, status;
  final Map<String, num?> per100g;
  factory FoodReference.fromJson(Map<String, dynamic> json) => FoodReference(
    json['id'] as String,
    json['name'] as String,
    json['source'] as String,
    json['status'] as String,
    (json['per100g'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, v as num?),
    ),
  );
}

/// Ukuran rumah tangga milik pengguna untuk satu makanan (mis. "1 centong" = 100 g). Tidak ada tabel konversi umum.
class PortionMeasure {
  PortionMeasure.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      label = j['label'] as String,
      grams = j['grams'] as num,
      basis = j['basis'] as String;
  final String id, label, basis;
  final num grams;
  String get basisLabel => basis == 'weighed' ? 'ditimbang' : 'perkiraanmu';
}

/// Baris Tabel Komposisi Pangan Indonesia (OCR + pemeriksaan konsistensi otomatis, bukan diperiksa manusia).
class ReferenceFood {
  ReferenceFood.fromJson(Map<String, dynamic> j)
    : code = j['code'] as String,
      name = j['name'] as String,
      provenance = j['provenance'] as String,
      source = j['source'] as String,
      completeness = j['completeness'] as String,
      per100g = (j['per100g'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v as num?),
      );
  final String code, name, provenance, source, completeness;
  final Map<String, num?> per100g;
  String get summary {
    final kcal = per100g['calories'];
    return '${kcal == null ? 'Energi belum tersedia' : '${kcal.round()} kkal'} per 100 gram';
  }
}

/// Hasil dari sumber luar (Open Food Facts / USDA). Belum tersimpan; menjadi makanan pribadi
/// berstatus "estimated" hanya setelah pengguna memilihnya.
class FoodCandidate {
  FoodCandidate.fromJson(Map<String, dynamic> j)
    : externalId = j['externalId'] as String,
      name = j['name'] as String,
      brand = j['brand'] as String?,
      source = j['source'] as String,
      completeness = j['completeness'] as String,
      per100g = (j['per100g'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v as num?),
      );
  final String externalId, name, source, completeness;
  final String? brand;
  final Map<String, num?> per100g;

  String get completenessLabel => switch (completeness) {
    'COMPLETE' => 'Data gizi lengkap',
    'PARTIAL' => 'Data gizi sebagian',
    _ => 'Tanpa data gizi',
  };
}

class ExternalSearch {
  ExternalSearch(this.status, this.items);
  final String status; // OK | PARTIAL | UNAVAILABLE
  final List<FoodCandidate> items;
}

/// Hasil pencarian kode batang. `status`: FOUND | NOT_FOUND | UNAVAILABLE.
class BarcodeLookup {
  BarcodeLookup(this.status, this.candidate);
  final String status;
  final FoodCandidate? candidate;
}

/// Hasil pembacaan label gizi (OCR). `status`: READ | NO_NUTRITION | UNAVAILABLE.
class LabelScan {
  LabelScan.fromJson(Map<String, dynamic> j)
    : status = j['status'] as String,
      code = j['code'] as String?,
      candidate = j['candidate'] is Map<String, dynamic>
          ? FoodCandidate.fromJson(j['candidate'] as Map<String, dynamic>)
          : null,
      rawText = (j['rawText'] as String?) ?? '',
      basis = (j['label'] as Map<String, dynamic>?)?['basis'] as String?,
      servingGrams =
          (j['label'] as Map<String, dynamic>?)?['servingGrams'] as num?,
      printed =
          ((j['label'] as Map<String, dynamic>?)?['printed']
                  as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as num?)) ??
          const {};
  final String status;
  final String? code, basis;
  final FoodCandidate? candidate;
  final String rawText;
  final num? servingGrams;
  final Map<String, num?> printed;
}

class PhotoMatch {
  PhotoMatch(
    this.name,
    this.confidence,
    this.matches, [
    this.reference = const [],
  ]);
  final String name, confidence;
  final List<FoodReference> matches;

  /// Padanan gizi dari Tabel Komposisi Pangan Indonesia (pencarian kata + makna). Kosong bila tidak ada yang cocok.
  final List<ReferenceFood> reference;
  String get confidenceLabel => switch (confidence) {
    'high' => 'Cukup yakin',
    'medium' => 'Kurang yakin',
    _ => 'Ragu',
  };
}

/// Hasil pengenalan foto makanan. `status`: IDENTIFIED | NOT_FOOD | UNAVAILABLE. Hanya nama, tanpa gizi/berat.
class PhotoScan {
  PhotoScan.fromJson(Map<String, dynamic> j)
    : status = j['status'] as String,
      code = j['code'] as String?,
      items = ((j['items'] as List?) ?? const [])
          .map((v) => v as Map<String, dynamic>)
          .map(
            (m) => PhotoMatch(
              m['name'] as String,
              m['confidence'] as String,
              ((m['matches'] as List?) ?? const [])
                  .map((f) => FoodReference.fromJson(f as Map<String, dynamic>))
                  .toList(),
              ((m['reference'] as List?) ?? const [])
                  .map((f) => ReferenceFood.fromJson(f as Map<String, dynamic>))
                  .toList(),
            ),
          )
          .toList(),
      modelHint = j['modelHint'] is Map<String, dynamic>
          ? ModelHint.fromJson(j['modelHint'] as Map<String, dynamic>)
          : null;
  final String status;
  final String? code;
  final List<PhotoMatch> items;

  /// Perkiraan model yang masih diuji; terpisah dari item dan tidak pernah dicatat otomatis. Null bila tidak ada/tidak yakin.
  final ModelHint? modelHint;
}

class ModelHint {
  ModelHint.fromJson(Map<String, dynamic> j)
    : label = j['label'] as String,
      probability = (j['probability'] as num).toDouble(),
      note = (j['note'] as String?) ?? '';
  final String label, note;
  final double probability;
  int get percent => (probability * 100).round();
}

class MealItemDraft {
  const MealItemDraft({
    this.id,
    this.foodId,
    required this.name,
    required this.quantity,
    required this.unit,
    this.grams,
    this.gramsBasis,
    this.per100g = const {},
    this.source = 'user_reported',
    this.status = 'unknown',
  });
  final String? id, foodId, gramsBasis;
  final String name, unit, source, status;
  final num quantity;
  final num? grams;
  final Map<String, num?> per100g;
  factory MealItemDraft.fromJson(Map<String, dynamic> json) => MealItemDraft(
    id: json['id'] as String?,
    foodId: json['foodId'] as String?,
    name: json['name'] as String,
    quantity: json['quantity'] as num,
    unit: json['unit'] as String,
    grams: json['grams'] as num?,
    gramsBasis: json['gramsBasis'] as String?,
    per100g: (json['per100g'] as Map<String, dynamic>? ?? {}).map(
      (k, v) => MapEntry(k, v as num?),
    ),
    source: json['source'] as String? ?? 'user_reported',
    status: json['status'] as String? ?? 'unknown',
  );
  Map<String, dynamic> toInput() => {
    if (id != null) 'id': id,
    'foodId': foodId,
    'name': name,
    'quantity': quantity,
    'unit': unit,
    'grams': grams,
    'gramsBasis': gramsBasis,
  };
  num? nutrient(String key) {
    final amount = unit == 'g' ? quantity : grams;
    final ref = per100g[key];
    return amount == null || ref == null ? null : ref * amount / 100;
  }
}

class MealRecord {
  MealRecord({
    required this.id,
    required this.category,
    required this.consumedAt,
    required this.localDate,
    required this.localTime,
    required this.timezone,
    required this.version,
    required this.items,
    required this.totals,
    this.notes,
    this.archived = false,
  });
  final String id, category, localDate, localTime, timezone;
  final DateTime consumedAt;
  final int version;
  final List<MealItemDraft> items;
  final Map<String, NutrientTotal> totals;
  final String? notes;
  final bool archived;
  factory MealRecord.fromJson(Map<String, dynamic> json) => MealRecord(
    id: json['id'] as String,
    category: json['category'] as String,
    consumedAt: DateTime.parse(json['consumedAt'] as String),
    localDate: json['localDate'] as String,
    localTime: json['localTime'] as String,
    timezone: json['timezone'] as String,
    version: json['version'] as int,
    notes: json['notes'] as String?,
    archived: json['archivedAt'] != null,
    items: (json['items'] as List)
        .map((v) => MealItemDraft.fromJson(v as Map<String, dynamic>))
        .toList(),
    totals: (json['totals'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, NutrientTotal.fromJson(v as Map<String, dynamic>)),
    ),
  );
}

class MealPage {
  const MealPage(this.items, this.nextCursor, this.timezone);
  final List<MealRecord> items;
  final String? nextCursor;
  final String timezone;
  factory MealPage.fromJson(Map<String, dynamic> json) => MealPage(
    (json['items'] as List)
        .map((v) => MealRecord.fromJson(v as Map<String, dynamic>))
        .toList(),
    json['nextCursor'] as String?,
    json['timezone'] as String,
  );
}
