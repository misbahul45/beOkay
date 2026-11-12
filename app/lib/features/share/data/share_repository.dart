import '../../../core/network/account_scoped_repository.dart';

class SummaryStat {
  SummaryStat.fromJson(Map<String, dynamic> j)
    : label = j['label'] as String,
      value = j['value'] as num?,
      unit = j['unit'] as String?,
      ready = j['state'] == 'READY',
      sampleCount = (j['sampleCount'] as num?)?.toInt() ?? 0,
      sampleUnit = (j['sampleUnit'] as String?) ?? '',
      daysWithData =
          ((j['coverage'] as Map?)?['daysWithData'] as num?)?.toInt() ?? 0,
      totalDays = ((j['coverage'] as Map?)?['totalDays'] as num?)?.toInt() ?? 0;
  final String label, sampleUnit;
  final num? value;
  final String? unit;
  final bool ready;
  final int sampleCount, daysWithData, totalDays;
  String get display {
    if (value == null) return '–';
    final v = value!.toDouble();
    final t = v == v.roundToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(1).replaceAll('.', ',');
    return unit == null ? t : '$t $unit';
  }
}

class SummaryItem {
  SummaryItem(this.label, this.value, this.date);
  final String label, value, date;
}

class ReportSummary {
  ReportSummary.fromJson(Map<String, dynamic> j)
    : name = ((j['person'] as Map)['name'] as String?) ?? '',
      days = (j['days'] as num).toInt(),
      start = (j['period'] as Map)['start'] as String,
      end = (j['period'] as Map)['end'] as String,
      generated =
          '${(j['generatedLocal'] as Map)['localDate']} ${(j['generatedLocal'] as Map)['localTime']}',
      statistics = [
        for (final s in j['statistics'] as List)
          SummaryStat.fromJson(s as Map<String, dynamic>),
      ],
      measures = [
        for (final v in [...(j['vitals'] as List), ...(j['labs'] as List)])
          SummaryItem(
            (v as Map)['label'] as String,
            v['value'] as String,
            v['date'] as String,
          ),
      ],
      medications = [
        for (final m in j['medications'] as List)
          [
            (m as Map)['name'],
            m['strength'],
            m['instructions'],
          ].whereType<String>().join(' · '),
      ],
      stepsMedian = (j['steps'] as Map?)?['medianSteps'] as num?,
      stepsDays = ((j['steps'] as Map?)?['daysWithData'] as num?)?.toInt() ?? 0,
      disclaimer = j['disclaimer'] as String,
      version = j['version'] as String;
  final String name, start, end, generated, disclaimer, version;
  final int days, stepsDays;
  final List<SummaryStat> statistics;
  final List<SummaryItem> measures;
  final List<String> medications;
  final num? stepsMedian;
}

class ShareLinkView {
  ShareLinkView.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      periodDays = (j['periodDays'] as num).toInt(),
      label = j['label'] as String?,
      expiresAt = DateTime.parse(j['expiresAt'] as String),
      active = j['active'] == true,
      accessCount = (j['accessCount'] as num?)?.toInt() ?? 0,
      url = j['url'] as String?;
  final String id;
  final int periodDays, accessCount;
  final String? label, url;
  final DateTime expiresAt;
  final bool active;
}

class ShareRepository extends AccountScopedRepository {
  ShareRepository(super.api, {required super.isCurrentAccount});

  Future<ReportSummary> summary(int days) async => ReportSummary.fromJson(
    (await api.get('/api/me/report-summary?days=$days')).object,
  );

  Future<List<ShareLinkView>> links() async => [
    for (final l
        in (await api.get('/api/me/share-links')).object['items'] as List)
      ShareLinkView.fromJson(l as Map<String, dynamic>),
  ];

  Future<ShareLinkView> create({
    required int periodDays,
    required int hours,
    String? label,
  }) async => ShareLinkView.fromJson(
    (await write('POST', '/api/me/share-links', {
      'periodDays': periodDays,
      'hours': hours,
      'label': ?label,
      'confirm': true,
    })).object,
  );

  Future<void> revoke(String id) =>
      write('POST', '/api/me/share-links/$id/revoke', const {});
}
