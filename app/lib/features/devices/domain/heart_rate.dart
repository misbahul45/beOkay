enum MetricAvailability {
  hasData,
  noData,
  notEnabled,
  permissionRequired,
  staleData,
}

MetricAvailability availabilityFrom(String? wire) => switch (wire) {
  'HAS_DATA' => MetricAvailability.hasData,
  'NOT_ENABLED' => MetricAvailability.notEnabled,
  'PERMISSION_REQUIRED' => MetricAvailability.permissionRequired,
  'STALE_DATA' => MetricAvailability.staleData,
  _ => MetricAvailability.noData,
};

class HeartRateDay {
  HeartRateDay.fromJson(Map<String, dynamic> j)
    : date = j['date'] as String,
      observedBuckets = (j['observedBuckets'] as num?)?.toInt() ?? 0,
      sampleCount = (j['sampleCount'] as num?)?.toInt() ?? 0,
      coverage = (j['coverage'] as num?)?.toDouble() ?? 0,
      minimum = (j['minimum'] as num?)?.toInt(),
      maximum = (j['maximum'] as num?)?.toInt(),
      average = (j['average'] as num?)?.toDouble(),
      resting = (j['restingHeartRate'] as num?)?.toInt(),
      lastMeasurementAt = DateTime.tryParse(
        (j['lastMeasurementAt'] as String?) ?? '',
      ),
      needsReview = j['needsReview'] == true,
      insufficient = j['insufficient'] == true;
  final String date;
  final int observedBuckets, sampleCount;
  final double coverage;
  final int? minimum, maximum, resting;
  final double? average;
  final DateTime? lastMeasurementAt;
  final bool needsReview, insufficient;

  bool get hasData => sampleCount > 0 || resting != null;
}

class HeartRateLatest {
  HeartRateLatest.fromJson(Map<String, dynamic> j)
    : bpm = (j['bpm'] as num).toInt(),
      windowStart = DateTime.parse(j['windowStart'] as String),
      origin = j['dataOrigin'] as String?,
      deviceType = j['deviceType'] as String?,
      simulated = j['simulated'] == true;
  final int bpm;
  final DateTime windowStart;
  final String? origin, deviceType;
  final bool simulated;
}

class RestingLatest {
  RestingLatest.fromJson(Map<String, dynamic> j)
    : bpm = (j['bpm'] as num).toInt(),
      measuredAt = DateTime.parse(j['measuredAt'] as String),
      simulated = j['simulated'] == true;
  final int bpm;
  final DateTime measuredAt;
  final bool simulated;
}

class HeartRateSummary {
  HeartRateSummary.fromJson(Map<String, dynamic> j)
    : days = (j['days'] as num).toInt(),
      series = [
        for (final d in (j['series'] as List))
          HeartRateDay.fromJson(d as Map<String, dynamic>),
      ],
      latest = j['latest'] is Map<String, dynamic>
          ? HeartRateLatest.fromJson(j['latest'] as Map<String, dynamic>)
          : null,
      restingLatest = j['restingLatest'] is Map<String, dynamic>
          ? RestingLatest.fromJson(j['restingLatest'] as Map<String, dynamic>)
          : null,
      freshness = (j['freshness'] as String?) ?? 'NO_DATA',
      simulated = j['simulated'] == true,
      methodology = (j['methodology'] as String?) ?? '',
      notice = (j['notice'] as String?) ?? '',
      heartRateEnabled = ((j['enabled'] as Map?)?['heartRate']) == true,
      restingEnabled = ((j['enabled'] as Map?)?['restingHeartRate']) == true;
  final int days;
  final List<HeartRateDay> series;
  final HeartRateLatest? latest;
  final RestingLatest? restingLatest;
  final String freshness, methodology, notice;
  final bool simulated, heartRateEnabled, restingEnabled;

  bool get hasData => series.any((d) => d.hasData);
}

class HeartRateBucketView {
  HeartRateBucketView.fromJson(Map<String, dynamic> j)
    : start = DateTime.parse(j['start'] as String),
      min = (j['min'] as num).toInt(),
      max = (j['max'] as num).toInt(),
      avg = (j['avg'] as num).toDouble(),
      sampleCount = (j['sampleCount'] as num).toInt(),
      origin = j['dataOrigin'] as String?,
      needsReview = j['needsReview'] == true,
      simulated = j['simulated'] == true;
  final DateTime start;
  final int min, max, sampleCount;
  final double avg;
  final String? origin;
  final bool needsReview, simulated;
}

class HeartRateDayDetail {
  HeartRateDayDetail.fromJson(Map<String, dynamic> j)
    : summary = HeartRateDay.fromJson(j['summary'] as Map<String, dynamic>),
      buckets = [
        for (final b in (j['buckets'] as List))
          HeartRateBucketView.fromJson(b as Map<String, dynamic>),
      ],
      resting = [
        for (final r in (j['resting'] as List? ?? const []))
          RestingLatest.fromJson(r as Map<String, dynamic>),
      ],
      methodology = (j['methodology'] as String?) ?? '',
      notice = (j['notice'] as String?) ?? '';
  final HeartRateDay summary;
  final List<HeartRateBucketView> buckets;
  final List<RestingLatest> resting;
  final String methodology, notice;
}

class DeviceMetricToday {
  DeviceMetricToday(this.availability, this.value);
  final MetricAvailability availability;
  final Map<String, dynamic>? value;

  static DeviceMetricToday from(Object? j) {
    final m = j is Map<String, dynamic> ? j : const <String, dynamic>{};
    return DeviceMetricToday(
      availabilityFrom(m['availability'] as String?),
      m['value'] as Map<String, dynamic>?,
    );
  }

  bool get simulated => value?['simulated'] == true;
}

class DeviceToday {
  DeviceToday.fromJson(Map<String, dynamic> j)
    : steps = DeviceMetricToday.from(j['steps']),
      heartRate = DeviceMetricToday.from(j['heartRate']),
      sleep = DeviceMetricToday.from(j['sleep']),
      activity = DeviceMetricToday.from(j['activity']);
  final DeviceMetricToday steps, heartRate, sleep, activity;

  bool get anyEnabled => [
    steps,
    heartRate,
    sleep,
    activity,
  ].any((m) => m.availability != MetricAvailability.notEnabled);
}
