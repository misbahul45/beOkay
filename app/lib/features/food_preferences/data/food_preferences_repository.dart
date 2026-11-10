import '../../../core/network/account_scoped_repository.dart';

const preferenceKindLabels = {
  'allergy': 'Alergi',
  'restriction': 'Pembatasan',
  'dislike': 'Tidak suka',
  'preference': 'Suka',
};

/// Istilah siap pakai; pembatasan gaya makan mengikuti preset di server.
const restrictionPresets = [
  ('halal', 'Halal'),
  ('vegetarian', 'Vegetarian'),
  ('vegan', 'Vegan'),
  ('bebas babi', 'Bebas babi'),
];
const commonAllergens = [
  ('kacang', 'Kacang'),
  ('udang', 'Udang'),
  ('ikan', 'Ikan'),
  ('telur', 'Telur'),
  ('susu', 'Susu'),
  ('gluten', 'Gluten'),
  ('kedelai', 'Kedelai'),
  ('wijen', 'Wijen'),
];

class FoodPreference {
  FoodPreference.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      kind = j['kind'] as String,
      term = j['term'] as String,
      label = j['label'] as String,
      strict = j['severity'] == 'strict',
      version = j['version'] as int;
  final String id, kind, term, label;
  final bool strict;
  final int version;
}

/// Hasil pengecekan satu nama makanan. Berbasis NAMA; [noMatch] tidak pernah berarti aman.
class PreferenceCheck {
  PreferenceCheck.fromJson(Map<String, dynamic> j)
    : name = j['name'] as String,
      status = j['status'] as String,
      labels = [
        for (final m in (j['matches'] as List))
          (m as Map<String, dynamic>)['label'] as String,
      ],
      strictMatch = [
        for (final m in (j['matches'] as List)) m as Map<String, dynamic>,
      ].any((m) => m['severity'] == 'strict');
  final String name, status;
  final List<String> labels;
  final bool strictMatch;
  bool get excluded => status == 'EXCLUDED';
  bool get warning => status == 'WARNING';
  bool get noMatch => status == 'NO_MATCH_FOUND';
}

class PreferenceChecks {
  const PreferenceChecks(this.hasStrictConstraints, this.byName);
  final bool hasStrictConstraints;
  final Map<String, PreferenceCheck> byName;
  static const empty = PreferenceChecks(false, {});
  PreferenceCheck? of(String name) => byName[name];
}

class FoodPreferencesRepository extends AccountScopedRepository {
  FoodPreferencesRepository(
    super.api, {
    required super.isCurrentAccount,
    super.enqueueOffline,
  });

  Future<List<FoodPreference>> list() async =>
      ((await api.get('/api/me/food-preferences')).object['items'] as List)
          .map((v) => FoodPreference.fromJson(v as Map<String, dynamic>))
          .toList();

  Future<FoodPreference> add({
    required String kind,
    required String term,
  }) async => FoodPreference.fromJson(
    (await write('POST', '/api/me/food-preferences', {
      'kind': kind,
      'term': term,
      'label': _label(term),
    })).object,
  );

  /// Label tampilan: huruf pertama kapital (server memakai preset bila istilahnya baku).
  static String _label(String term) {
    final t = term.trim();
    return t.length < 2 ? t : t[0].toUpperCase() + t.substring(1);
  }

  Future<void> archive(FoodPreference p) async => write(
    'PATCH',
    '/api/me/food-preferences/${p.id}',
    {'expectedVersion': p.version, 'archived': true},
  );

  /// Satu panggilan untuk banyak nama. Gagal = tanpa lencana (bukan klaim aman).
  Future<PreferenceChecks> check(List<String> names) async {
    final unique = {
      ...names,
    }.where((n) => n.trim().isNotEmpty).take(50).toList();
    if (unique.isEmpty) return PreferenceChecks.empty;
    final r = (await write('POST', '/api/me/food-preferences/check', {
      'items': [
        for (final n in unique) {'name': n},
      ],
    })).object;
    final results = [
      for (final v in (r['results'] as List))
        PreferenceCheck.fromJson(v as Map<String, dynamic>),
    ];
    return PreferenceChecks(r['hasStrictConstraints'] == true, {
      for (final c in results) c.name: c,
    });
  }
}
