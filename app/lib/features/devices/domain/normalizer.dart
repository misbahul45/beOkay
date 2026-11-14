import 'dart:math' as math;

import '../../activity/data/device_activity_source.dart' show DeviceSession;
import '../data/health_source.dart';
import 'measurements.dart';

const bucketMillis = 5 * 60 * 1000;
const hrDomainMin = 20;
const hrDomainMax = 300;

class NormalizedBatch {
  const NormalizedBatch({
    this.steps = const [],
    this.heartRate = const [],
    this.resting = const [],
    this.sleep = const [],
    this.weights = const [],
    this.glucose = const [],
    this.workouts = const [],
    this.rejected = const {},
    this.sleepConflicts = 0,
  });
  final List<StepsDay> steps;
  final List<HeartRateBucketPayload> heartRate;
  final List<RestingHeartRatePayload> resting;
  final List<SleepPayload> sleep;
  final List<WeightPayload> weights;
  final List<GlucosePayload> glucose;
  final List<DeviceSession> workouts;
  final Map<String, int> rejected;
  final int sleepConflicts;

  int get rejectedTotal => rejected.values.fold(0, (a, b) => a + b);
  bool get isEmpty =>
      steps.isEmpty &&
      heartRate.isEmpty &&
      resting.isEmpty &&
      sleep.isEmpty &&
      weights.isEmpty &&
      glucose.isEmpty &&
      workouts.isEmpty;
}

String? _dominant(Iterable<String?> values) {
  final counts = <String, int>{};
  for (final v in values) {
    if (v != null) counts[v] = (counts[v] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

double _round2(double v) => (v * 100).round() / 100;

class _Acc {
  _Acc(this.origin, this.start);
  final String origin;
  final int start;
  final samples = <RawMeasurement>[];
  num sum = 0;
  num min = double.infinity;
  num max = double.negativeInfinity;
}

class HealthNormalizer {
  const HealthNormalizer({this._clock});
  final DateTime Function()? _clock;

  DateTime get _now => (_clock ?? DateTime.now)();

  NormalizedBatch normalize(HealthReadResult read) {
    final rejected = <String, int>{};
    void reject(String reason) =>
        rejected[reason] = (rejected[reason] ?? 0) + 1;
    final now = _now;
    final horizon = now.add(const Duration(minutes: 5));
    final today = isoDate(now);

    final steps = <String, StepsDay>{};
    final hr = <RawMeasurement>[];
    final resting = <String, RestingHeartRatePayload>{};
    final sleep = <String, SleepPayload>{};
    final weights = <String, WeightPayload>{};
    final glucose = <String, GlucosePayload>{};

    for (final m in read.measurements) {
      if (!m.value.isFinite) {
        reject('NOT_A_NUMBER');
        continue;
      }
      if (m.startTime.isAfter(horizon)) {
        reject('FUTURE_TIMESTAMP');
        continue;
      }
      switch (m.metric) {
        case WearableMetric.steps:
          final date = isoDate(m.startTime);
          if (m.value < 0 || m.value > 200000 || date.compareTo(today) > 0) {
            reject('STEPS_INVALID');
          } else {
            steps[date] = StepsDay(date, m.value.round(), m.origin);
          }
        case WearableMetric.heartRate:
          if (m.value < hrDomainMin || m.value > hrDomainMax) {
            reject('HEART_RATE_OUT_OF_DOMAIN');
          } else {
            hr.add(m);
          }
        case WearableMetric.restingHeartRate:
          if (m.value < hrDomainMin || m.value > hrDomainMax) {
            reject('HEART_RATE_OUT_OF_DOMAIN');
          } else {
            resting[m.id] = RestingHeartRatePayload(
              externalId: m.id,
              measuredAt: m.startTime,
              bpm: m.value.round(),
              origin: m.origin,
              recordingMethod: m.recordingMethod,
              deviceType: m.deviceType,
            );
          }
        case WearableMetric.sleep:
          final minutes = m.endTime.difference(m.startTime).inSeconds / 60;
          if (minutes < 1 || minutes > 1440) {
            reject('SLEEP_DURATION_OUT_OF_RANGE');
          } else {
            sleep[m.id] = SleepPayload(
              externalId: m.id,
              startedAt: m.startTime,
              endedAt: m.endTime,
              origin: m.origin,
              recordingMethod: m.recordingMethod,
              deviceType: m.deviceType,
            );
          }
        case WearableMetric.weight:
          if (m.value < 10 || m.value > 500) {
            reject('WEIGHT_OUT_OF_RANGE');
          } else {
            weights[m.id] = WeightPayload(
              externalId: m.id,
              measuredAt: m.startTime,
              kg: _round2(m.value.toDouble()),
              origin: m.origin,
            );
          }
        case WearableMetric.glucose:
          if (m.value <= 0 || m.value > 2000) {
            reject('GLUCOSE_OUT_OF_RANGE');
          } else {
            glucose[m.id] = GlucosePayload(
              externalId: m.id,
              measuredAt: m.startTime,
              value: _round2(m.value.toDouble()),
              origin: m.origin,
            );
          }
        case WearableMetric.workouts:
          break;
      }
    }

    final workouts = <String, DeviceSession>{};
    for (final w in read.workouts) {
      if (w.durationMinutes < 1 || w.durationMinutes > 1440) {
        reject('WORKOUT_DURATION_OUT_OF_RANGE');
      } else {
        workouts[w.externalId] = w;
      }
    }

    final sleepList = sleep.values.toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    var conflicts = 0;
    for (var i = 1; i < sleepList.length; i++) {
      final a = sleepList[i - 1], b = sleepList[i];
      if (b.startedAt.isBefore(a.endedAt) && a.origin != b.origin) conflicts++;
    }

    return NormalizedBatch(
      steps: steps.values.toList()
        ..sort((a, b) => a.localDate.compareTo(b.localDate)),
      heartRate: bucketHeartRate(hr),
      resting: resting.values.toList()
        ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt)),
      sleep: sleepList,
      weights: weights.values.toList(),
      glucose: glucose.values.toList(),
      workouts: workouts.values.toList(),
      rejected: rejected,
      sleepConflicts: conflicts,
    );
  }

  List<HeartRateBucketPayload> bucketHeartRate(
    Iterable<RawMeasurement> samples,
  ) {
    final groups = <String, _Acc>{};
    for (final s in samples) {
      final start =
          (s.startTime.toUtc().millisecondsSinceEpoch ~/ bucketMillis) *
          bucketMillis;
      final origin = s.origin ?? 'unknown';
      final acc = groups.putIfAbsent(
        '$origin|$start',
        () => _Acc(origin, start),
      );
      acc.samples.add(s);
      acc.sum += s.value;
      acc.min = math.min(acc.min, s.value);
      acc.max = math.max(acc.max, s.value);
    }
    final out = [
      for (final g in groups.values)
        HeartRateBucketPayload(
          bucketStart: DateTime.fromMillisecondsSinceEpoch(
            g.start,
            isUtc: true,
          ),
          min: g.min.floor(),
          max: g.max.ceil(),
          avg: _round2(g.sum / g.samples.length),
          count: g.samples.length,
          origin: g.origin == 'unknown' ? null : g.origin,
          recordingMethod: g.samples.any((s) => s.recordingMethod == 'manual')
              ? 'manual'
              : _dominant(g.samples.map((s) => s.recordingMethod)),
          deviceType: _dominant(g.samples.map((s) => s.deviceType)),
        ),
    ]..sort((a, b) => a.bucketStart.compareTo(b.bucketStart));
    return out;
  }
}
