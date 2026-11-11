import 'package:intl/intl.dart';

import '../data/statistics.dart';

final _number = NumberFormat.decimalPattern('id_ID')..maximumFractionDigits = 1;
final _wholeNumber = NumberFormat.decimalPattern('id_ID')
  ..maximumFractionDigits = 0;

String formatValue(num v, {bool whole = false}) =>
    (whole ? _wholeNumber : _number).format(v);

enum InsightAction {
  openTrends('Lihat tren'),
  logMeal('Catat makanan'),
  openGlucose('Buka glukosa'),
  openMedication('Buka obat'),
  askCoach('Tanya Asisten'),
  createGoal('Buat target');

  const InsightAction(this.label);
  final String label;

  static InsightAction? fromWire(String code) => switch (code) {
    'OPEN_TRENDS' => openTrends,
    'LOG_MEAL' => logMeal,
    'OPEN_GLUCOSE' => openGlucose,
    'OPEN_MEDICATION' => openMedication,
    'ASK_COACH' => askCoach,
    'CREATE_GOAL' => createGoal,
    _ => null,
  };
}

enum ComparisonValidity { valid, tooLittleData, unavailable }

class InsightPresentation {
  const InsightPresentation({
    required this.code,
    required this.domain,
    required this.category,
    required this.headline,
    required this.supporting,
    required this.action,
    required this.priority,
    required this.source,
  });

  final String code, domain, category, headline, supporting;
  final InsightAction? action;
  final double priority;
  final InsightCardData source;
}

class MetricPresentation {
  const MetricPresentation({
    required this.domain,
    required this.label,
    required this.value,
    required this.unit,
    required this.caption,
    required this.statistic,
  });

  final String domain, label, caption;
  final String? value, unit;
  final Statistic? statistic;
  bool get hasValue => value != null;
}

ComparisonValidity comparisonValidity(Statistic s) {
  if (s.comparison == null || !s.ready) return ComparisonValidity.unavailable;
  final minDays = s.domain == 'glucose' ? 1 : 2;
  if (s.daysWithData < minDays || s.sampleCount < s.minimumSample) {
    return ComparisonValidity.tooLittleData;
  }
  return ComparisonValidity.valid;
}

String? comparisonSentence(Statistic s, int days, {bool withPrevious = false}) {
  if (comparisonValidity(s) != ComparisonValidity.valid) return null;
  final c = s.comparison!;
  final unit = s.unit == null ? '' : ' ${s.unit}';
  final previous = withPrevious ? ' (${formatValue(c.value)}$unit)' : '';
  if (c.direction == 'SAME') {
    return 'Sama dengan catatan $days hari sebelumnya$previous.';
  }
  final up = c.change > 0;
  final word = s.domain == 'glucose'
      ? (up ? 'tinggi' : 'rendah')
      : (up ? 'banyak' : 'sedikit');
  return '${formatValue(c.change.abs())}$unit lebih $word dari catatan $days hari sebelumnya$previous.';
}

String coverageSentence(int have, int total) => have >= total
    ? 'Ada catatan setiap hari'
    : 'Ada catatan di $have dari $total hari';

const _categories = {
  'activity': 'Aktivitas',
  'nutrition': 'Nutrisi',
  'glucose': 'Glukosa',
  'medication': 'Jadwal obat',
  'logging': 'Pencatatan',
};

String categoryFor(String domain) => _categories[domain] ?? 'Catatan';

InsightPresentation presentInsight(InsightCardData c, Statistics s) {
  final n = s.days;
  final category = categoryFor(c.domain);
  final fallbackAction = c.actions
      .map(InsightAction.fromWire)
      .whereType<InsightAction>()
      .firstOrNull;
  final coverage = c.totalDays == 0 ? 0.0 : c.daysWithData / c.totalDays;

  switch (c.code) {
    case 'ACTIVITY_PERIOD_CHANGE':
      final total = s.byId('activity.total_minutes');
      if (total != null && total.value != null) {
        final cmp = comparisonSentence(total, n);
        final change = total.comparison;
        final significance = change == null || change.value == 0
            ? 0.0
            : (change.change.abs() / change.value).clamp(0, 1).toDouble();
        return InsightPresentation(
          code: c.code,
          domain: c.domain,
          category: category,
          headline: '${formatValue(total.value!, whole: true)} menit tercatat',
          supporting:
              cmp ?? 'Data ada untuk ${total.daysWithData} dari $n hari.',
          action: InsightAction.openTrends,
          priority: 40 + 30 * significance * coverage + (cmp == null ? 0 : 5),
          source: c,
        );
      }
    case 'ACTIVITY_WEEKDAY_PATTERN':
      final weekdays = c.title.contains('hari kerja');
      return InsightPresentation(
        code: c.code,
        domain: c.domain,
        category: category,
        headline: weekdays
            ? 'Lebih sering aktif di hari kerja'
            : 'Lebih sering aktif di akhir pekan',
        supporting: c.evidence.map((e) => '${e.label}: ${e.value}').join(' · '),
        action: InsightAction.openTrends,
        priority: 20 + 15 * coverage,
        source: c,
      );
    case 'NUTRITION_LOGGING_COVERAGE':
      final logged = s.byId('nutrition.logged_days');
      final have = logged?.value?.round() ?? c.daysWithData;
      return InsightPresentation(
        code: c.code,
        domain: c.domain,
        category: category,
        headline: 'Makan tercatat di $have dari $n hari',
        supporting: 'Rata-rata gizi hanya mewakili hari yang tercatat.',
        action: InsightAction.logMeal,
        priority: 35 + 15 * (1 - coverage),
        source: c,
      );
    case 'GLUCOSE_FASTING_CONTEXT':
      final fasting = s.byId('glucose.fasting_median');
      if (fasting != null && fasting.value != null) {
        final unit = fasting.unit ?? s.glucoseUnit;
        final cmp = comparisonSentence(fasting, n);
        final few = fasting.sampleCount < 3;
        return InsightPresentation(
          code: c.code,
          domain: c.domain,
          category: 'Glukosa puasa',
          headline: 'Median ${formatValue(fasting.value!)} $unit',
          supporting: few
              ? 'Baru ${fasting.sampleCount} pengukuran puasa, belum cukup untuk melihat pola.'
              : (cmp ?? 'Belum bisa dibandingkan dengan periode sebelumnya.'),
          action: InsightAction.openGlucose,
          priority: few ? 25 : 45 + 10 * coverage,
          source: c,
        );
      }
    case 'MEDICATION_UNCONFIRMED':
      final med = s.byId('medication.confirmed');
      final unconfirmed = med?.detail?['unconfirmed']?.round();
      if (unconfirmed != null && unconfirmed > 0) {
        return InsightPresentation(
          code: c.code,
          domain: c.domain,
          category: category,
          headline: '$unconfirmed jadwal belum dikonfirmasi',
          supporting: 'Belum dikonfirmasi tidak berarti terlewat.',
          action: InsightAction.openMedication,
          priority: 60,
          source: c,
        );
      }
  }
  return InsightPresentation(
    code: c.code,
    domain: c.domain,
    category: category,
    headline: c.title,
    supporting: c.body,
    action: fallbackAction,
    priority: 10,
    source: c,
  );
}

List<InsightPresentation> prioritizeInsights(Statistics s) {
  final ranked = s.insights.map((c) => presentInsight(c, s)).toList()
    ..sort((a, b) {
      final p = b.priority.compareTo(a.priority);
      return p != 0 ? p : a.code.compareTo(b.code);
    });
  final seen = <String>{};
  final first = <InsightPresentation>[];
  final rest = <InsightPresentation>[];
  for (final i in ranked) {
    (seen.add(i.domain) ? first : rest).add(i);
  }
  return [...first, ...rest];
}

List<MetricPresentation> overviewMetrics(Statistics s) {
  final total = s.byId('activity.total_minutes');
  final active = s.byId('activity.active_days');
  final fasting = s.byId('glucose.fasting_median');
  final readings = s.byId('glucose.readings');
  final logged = s.byId('nutrition.logged_days');
  final med = s.byId('medication.confirmed');

  final activity = total != null && total.ready && (total.value ?? 0) > 0
      ? MetricPresentation(
          domain: 'activity',
          label: 'Aktivitas',
          value: formatValue(total.value!, whole: true),
          unit: 'menit',
          caption:
              '${active?.value?.round() ?? total.daysWithData} hari tercatat',
          statistic: total,
        )
      : MetricPresentation(
          domain: 'activity',
          label: 'Aktivitas',
          value: null,
          unit: null,
          caption: 'Belum ada sesi tercatat',
          statistic: total,
        );

  final MetricPresentation glucose;
  if (fasting != null && fasting.ready && fasting.value != null) {
    glucose = MetricPresentation(
      domain: 'glucose',
      label: 'Glukosa puasa',
      value: formatValue(fasting.value!),
      unit: fasting.unit ?? s.glucoseUnit,
      caption: 'Median catatanmu',
      statistic: fasting,
    );
  } else if (readings != null && (readings.value ?? 0) > 0) {
    glucose = MetricPresentation(
      domain: 'glucose',
      label: 'Glukosa',
      value: formatValue(readings.value!, whole: true),
      unit: 'pengukuran',
      caption: 'Median puasa belum cukup data',
      statistic: readings,
    );
  } else {
    glucose = MetricPresentation(
      domain: 'glucose',
      label: 'Glukosa',
      value: null,
      unit: null,
      caption: 'Belum ada pengukuran',
      statistic: readings ?? fasting,
    );
  }

  final nutritionDays = logged?.value?.round() ?? 0;
  final nutrition = nutritionDays > 0
      ? MetricPresentation(
          domain: 'nutrition',
          label: 'Nutrisi',
          value: '$nutritionDays',
          unit: 'hari',
          caption: 'Dengan catatan makan',
          statistic: logged,
        )
      : MetricPresentation(
          domain: 'nutrition',
          label: 'Nutrisi',
          value: null,
          unit: null,
          caption: 'Belum ada catatan makan',
          statistic: logged,
        );

  final scheduled = med?.detail?['scheduled']?.round() ?? 0;
  final confirmed = med?.value?.round() ?? 0;
  final medication = med != null && med.ready && scheduled > 0
      ? MetricPresentation(
          domain: 'medication',
          label: 'Obat',
          value: '$confirmed dari $scheduled',
          unit: null,
          caption: 'Jadwal dikonfirmasi',
          statistic: med,
        )
      : MetricPresentation(
          domain: 'medication',
          label: 'Obat',
          value: null,
          unit: null,
          caption: 'Belum ada jadwal obat',
          statistic: med,
        );

  return [activity, glucose, nutrition, medication];
}

String sourceLabel(String sourceType) => switch (sourceType) {
  'USER_REPORTED_MEALS' => 'Catatan makan yang kamu masukkan',
  'USER_AND_DEVICE_ACTIVITY' => 'Sesi manual dan impor perangkat',
  'MANUAL_GLUCOMETER' => 'Glukometer manual, dilaporkan sendiri',
  'USER_CONFIRMED_MEDICATION' => 'Jadwal obat dan konfirmasimu',
  _ => 'Semua catatanmu',
};
