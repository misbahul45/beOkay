double? _d(Object? v) => (v as num?)?.toDouble();

class StatComparison {
  StatComparison.fromJson(Map<String, dynamic> j)
    : value = _d(j['value'])!,
      change = _d(j['change'])!,
      direction = j['direction'] as String,
      start = (j['range'] as Map)['start'] as String,
      end = (j['range'] as Map)['end'] as String;

  final double value, change;
  final String direction, start, end;
}

class Statistic {
  Statistic.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      domain = j['domain'] as String,
      label = j['label'] as String,
      value = _d(j['value']),
      unit = j['unit'] as String?,
      category = j['category'] as String,
      ready = j['state'] == 'READY',
      sourceType = j['sourceType'] as String,
      sampleCount = j['sampleCount'] as int,
      sampleUnit = j['sampleUnit'] as String,
      minimumSample = j['minimumSample'] as int,
      coverageStatus = (j['coverage'] as Map)['status'] as String,
      daysWithData = (j['coverage'] as Map)['daysWithData'] as int,
      totalDays = (j['coverage'] as Map)['totalDays'] as int,
      derivation = j['derivation'] as String,
      comparison = j['comparison'] is Map<String, dynamic>
          ? StatComparison.fromJson(j['comparison'] as Map<String, dynamic>)
          : null,
      detail = (j['detail'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, _d(v)),
      ),
      limitations = (j['limitations'] as List).cast<String>(),
      analysisVersion = j['analysisVersion'] as String,
      computedAt = DateTime.parse(j['computedAt'] as String),
      rangeStart = (j['range'] as Map)['start'] as String,
      rangeEnd = (j['range'] as Map)['end'] as String;

  final String id, domain, label, category, sourceType, sampleUnit;
  final String coverageStatus, derivation, analysisVersion;
  final String rangeStart, rangeEnd;
  final String? unit;
  final double? value;
  final bool ready;
  final int sampleCount, minimumSample, daysWithData, totalDays;
  final StatComparison? comparison;
  final Map<String, double?>? detail;
  final List<String> limitations;
  final DateTime computedAt;
}

class InsightEvidence {
  const InsightEvidence(this.label, this.value);
  final String label, value;
}

class InsightCardData {
  InsightCardData.fromJson(Map<String, dynamic> j)
    : code = j['code'] as String,
      domain = j['domain'] as String,
      title = j['title'] as String,
      body = j['body'] as String,
      evidence = [
        for (final e in j['evidence'] as List)
          InsightEvidence((e as Map)['label'] as String, e['value'] as String),
      ],
      statisticIds = (j['statisticIds'] as List).cast<String>(),
      daysWithData = (j['coverage'] as Map)['daysWithData'] as int,
      totalDays = (j['coverage'] as Map)['totalDays'] as int,
      actions = (j['actions'] as List).cast<String>(),
      rulesVersion = j['rulesVersion'] as String;

  final String code, domain, title, body, rulesVersion;
  final List<InsightEvidence> evidence;
  final List<String> statisticIds, actions;
  final int daysWithData, totalDays;
}

class NutrientValue {
  const NutrientValue(this.value, this.coverage);
  final double? value;
  final String coverage;
}

class StatDay {
  StatDay.fromJson(Map<String, dynamic> j)
    : date = DateTime.parse(j['date'] as String),
      recorded = j['recorded'] as bool,
      meals = j['meals'] as int,
      nutrients = (j['nutrients'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(
          k,
          v == null
              ? null
              : NutrientValue(_d((v as Map)['value']), v['coverage'] as String),
        ),
      ),
      activityMinutes = j['activityMinutes'] as int?,
      glucose = [
        for (final g in j['glucose'] as List)
          (value: _d((g as Map)['value'])!, context: g['context'] as String),
      ];

  final DateTime date;
  final bool recorded;
  final int meals;
  final Map<String, NutrientValue?> nutrients;
  final int? activityMinutes;
  final List<({double value, String context})> glucose;

  double? grams(String nutrient) => nutrients[nutrient]?.value;
}

class Statistics {
  Statistics.fromJson(Map<String, dynamic> j)
    : days = (j['period'] as Map)['days'] as int,
      periodStart = (j['period'] as Map)['start'] as String,
      periodEnd = (j['period'] as Map)['end'] as String,
      comparisonStart = (j['comparisonPeriod'] as Map)['start'] as String,
      comparisonEnd = (j['comparisonPeriod'] as Map)['end'] as String,
      ready = j['analyticsState'] == 'READY',
      glucoseUnit = j['glucoseUnit'] as String,
      analysisVersion = j['analysisVersion'] as String,
      computedAt = DateTime.parse(j['computedAt'] as String),
      statistics = [
        for (final s in j['statistics'] as List)
          Statistic.fromJson(s as Map<String, dynamic>),
      ],
      insights = [
        for (final c in j['insights'] as List)
          InsightCardData.fromJson(c as Map<String, dynamic>),
      ],
      series = [
        for (final d in j['series'] as List)
          StatDay.fromJson(d as Map<String, dynamic>),
      ];

  final int days;
  final String periodStart, periodEnd, comparisonStart, comparisonEnd;
  final String glucoseUnit, analysisVersion;
  final bool ready;
  final DateTime computedAt;
  final List<Statistic> statistics;
  final List<InsightCardData> insights;
  final List<StatDay> series;

  Statistic? byId(String id) {
    for (final s in statistics) {
      if (s.id == id) return s;
    }
    return null;
  }
}
