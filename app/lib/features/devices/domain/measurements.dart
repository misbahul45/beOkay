import '../../activity/data/device_activity_source.dart' show validOrigin;

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class StepsDay {
  const StepsDay(this.localDate, this.steps, [this.origin]);
  final String localDate;
  final int steps;
  final String? origin;
  Map<String, dynamic> toJson() => {
    'localDate': localDate,
    'steps': steps,
    'dataOrigin': ?validOrigin(origin),
  };
}

class HeartRateBucketPayload {
  const HeartRateBucketPayload({
    required this.bucketStart,
    required this.min,
    required this.max,
    required this.avg,
    required this.count,
    this.origin,
    this.recordingMethod,
    this.deviceType,
  });
  final DateTime bucketStart;
  final int min, max, count;
  final double avg;
  final String? origin, recordingMethod, deviceType;
  Map<String, dynamic> toJson() => {
    'bucketStart': bucketStart.toUtc().toIso8601String(),
    'bpmMin': min,
    'bpmMax': max,
    'bpmAvg': avg,
    'sampleCount': count,
    'dataOrigin': ?validOrigin(origin),
    'recordingMethod': ?recordingMethod,
    'device': ?deviceType,
  };
}

class RestingHeartRatePayload {
  const RestingHeartRatePayload({
    required this.externalId,
    required this.measuredAt,
    required this.bpm,
    this.origin,
    this.recordingMethod,
    this.deviceType,
  });
  final String externalId;
  final DateTime measuredAt;
  final int bpm;
  final String? origin, recordingMethod, deviceType;
  Map<String, dynamic> toJson() => {
    'externalId': externalId,
    'measuredAt': measuredAt.toUtc().toIso8601String(),
    'bpm': bpm,
    'dataOrigin': ?validOrigin(origin),
    'recordingMethod': ?recordingMethod,
    'device': ?deviceType,
  };
}

class SleepPayload {
  const SleepPayload({
    required this.externalId,
    required this.startedAt,
    required this.endedAt,
    this.origin,
    this.recordingMethod,
    this.deviceType,
  });
  final String externalId;
  final DateTime startedAt, endedAt;
  final String? origin, recordingMethod, deviceType;
  Map<String, dynamic> toJson() => {
    'externalId': externalId,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'endedAt': endedAt.toUtc().toIso8601String(),
    'dataOrigin': ?validOrigin(origin),
    'recordingMethod': ?recordingMethod,
    'device': ?deviceType,
  };
}

class WeightPayload {
  const WeightPayload({
    required this.externalId,
    required this.measuredAt,
    required this.kg,
    this.origin,
  });
  final String externalId;
  final DateTime measuredAt;
  final double kg;
  final String? origin;
  Map<String, dynamic> toJson() => {
    'externalId': externalId,
    'measuredAt': measuredAt.toUtc().toIso8601String(),
    'kg': kg,
    'dataOrigin': ?validOrigin(origin),
  };
}

class GlucosePayload {
  const GlucosePayload({
    required this.externalId,
    required this.measuredAt,
    required this.value,
    this.origin,
  });
  final String externalId;
  final DateTime measuredAt;
  final double value;
  final String? origin;
  Map<String, dynamic> toJson() => {
    'externalId': externalId,
    'measuredAt': measuredAt.toUtc().toIso8601String(),
    'value': value,
    'unit': 'mg/dL',
    'specimen': 'unknown',
    'dataOrigin': ?validOrigin(origin),
  };
}
