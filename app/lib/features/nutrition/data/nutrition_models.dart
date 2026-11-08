import 'dart:math';

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

String newRecordId() {
  final bytes = List.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final s = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
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
