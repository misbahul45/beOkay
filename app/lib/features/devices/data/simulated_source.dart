import 'dart:math' as math;

import '../../activity/data/device_activity_source.dart' show DeviceSession;
import 'health_source.dart';

enum SimulationProfile {
  activeDay,
  lowActivityDay,
  noDataDay,
  partialDay,
  multipleSources,
  conflictingSources,
  staleMeasurements,
  permissionRevoked,
  offlineSynchronization,
}

extension SimulationProfileLabel on SimulationProfile {
  String get label => switch (this) {
    SimulationProfile.activeDay => 'Hari aktif',
    SimulationProfile.lowActivityDay => 'Hari minim aktivitas',
    SimulationProfile.noDataDay => 'Tanpa data',
    SimulationProfile.partialDay => 'Data sebagian',
    SimulationProfile.multipleSources => 'Dua sumber data',
    SimulationProfile.conflictingSources => 'Sumber bertentangan',
    SimulationProfile.staleMeasurements => 'Data lama',
    SimulationProfile.permissionRevoked => 'Izin dicabut',
    SimulationProfile.offlineSynchronization => 'Sinkron saat offline',
  };
}

const simulatorOrigin = 'beokay.simulator';
const simulatorSecondOrigin = 'beokay.simulator.phone';

double _noise(int seed) {
  final v = (seed * 1103515245 + 12345) & 0x7fffffff;
  return (v % 1000) / 1000;
}

class SimulatedHealthDataSource implements HealthDataSource {
  SimulatedHealthDataSource({
    this.profile = SimulationProfile.activeDay,
    DateTime Function()? clock,
    Set<WearableMetric>? granted,
    this.includeCompatibilityFixtures = false,
    this.hrDays = 2,
  }) : _clock = clock ?? DateTime.now,
       granted = granted ?? <WearableMetric>{};

  SimulationProfile profile;
  final DateTime Function() _clock;
  final Set<WearableMetric> granted;
  final bool includeCompatibilityFixtures;
  final int hrDays;

  @override
  String get sourceKey => 'simulated';

  @override
  bool get isSimulated => true;

  @override
  Future<SourceCapabilities> capabilities() async => const SourceCapabilities(
    platform: HealthPlatformState.available,
    backgroundRead: false,
    historyRead: false,
  );

  @override
  Future<bool> hasAccess(WearableMetric metric) async =>
      profile != SimulationProfile.permissionRevoked &&
      granted.contains(metric);

  @override
  Future<bool> requestAccess(WearableMetric metric) async {
    if (profile == SimulationProfile.permissionRevoked) return false;
    granted.add(metric);
    return true;
  }

  void revokeAll() => granted.clear();

  DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

  RawMeasurement _m(
    String id,
    WearableMetric metric,
    num value,
    String unit,
    DateTime start,
    DateTime end, {
    String origin = simulatorOrigin,
    String device = 'watch',
    String method = 'automatic',
  }) => RawMeasurement(
    id: id,
    metric: metric,
    value: value,
    unit: unit,
    startTime: start,
    endTime: end,
    origin: origin,
    recordingMethod: method,
    deviceType: device,
    deviceManufacturer: 'Simulasi',
    deviceModel: 'Jam Simulasi',
    isSimulated: true,
  );

  @override
  Future<HealthReadResult> read(HealthReadRequest request) async {
    final now = _clock();
    final shift = profile == SimulationProfile.staleMeasurements
        ? const Duration(days: 4)
        : Duration.zero;
    final cutoff = now.subtract(shift);
    final out = <RawMeasurement>[];
    final workouts = <DeviceSession>[];
    if (profile == SimulationProfile.noDataDay ||
        profile == SimulationProfile.permissionRevoked) {
      return const HealthReadResult();
    }
    for (final metric in request.metrics) {
      switch (metric) {
        case WearableMetric.steps:
          out.addAll(_steps(cutoff, request.stepsDays));
        case WearableMetric.heartRate:
          out.addAll(_heartRate(cutoff, request));
        case WearableMetric.restingHeartRate:
          out.addAll(_resting(cutoff, request));
        case WearableMetric.sleep:
          out.addAll(_sleep(cutoff, request));
        case WearableMetric.workouts:
          workouts.addAll(_workouts(cutoff, request));
        case WearableMetric.weight:
          if (includeCompatibilityFixtures) {
            final t = _midnight(cutoff).add(const Duration(hours: 7));
            if (t.isBefore(cutoff)) {
              out.add(
                _m(
                  'sim-weight-${t.millisecondsSinceEpoch}',
                  metric,
                  72.4,
                  'kg',
                  t,
                  t,
                  device: 'scale',
                ),
              );
            }
          }
        case WearableMetric.glucose:
          if (includeCompatibilityFixtures) {
            final t = _midnight(
              cutoff,
            ).add(const Duration(hours: 7, minutes: 30));
            if (t.isBefore(cutoff)) {
              out.add(
                _m(
                  'sim-glucose-${t.millisecondsSinceEpoch}',
                  metric,
                  104,
                  'mg/dL',
                  t,
                  t,
                  device: 'unknown',
                ),
              );
            }
          }
      }
    }
    return HealthReadResult(measurements: out, workouts: workouts);
  }

  List<RawMeasurement> _steps(DateTime now, int days) {
    final out = <RawMeasurement>[];
    for (var i = days - 1; i >= 0; i--) {
      final start = _midnight(now).subtract(Duration(days: i));
      if (profile == SimulationProfile.partialDay && i > 0) continue;
      final base = profile == SimulationProfile.lowActivityDay
          ? 2200 + _noise(start.day) * 1400
          : 8200 + _noise(start.day) * 3200;
      final fraction = i == 0 ? (now.hour * 60 + now.minute) / 1440 : 1.0;
      final end = i == 0 ? now : start.add(const Duration(days: 1));
      out.add(
        _m(
          'sim-steps-${start.millisecondsSinceEpoch}',
          WearableMetric.steps,
          (base * fraction).round(),
          'count',
          start,
          end,
          device: 'phone',
        ),
      );
    }
    return out;
  }

  List<RawMeasurement> _heartRate(DateTime now, HealthReadRequest request) {
    final out = <RawMeasurement>[];
    final lower = request.from.isAfter(now.subtract(Duration(days: hrDays)))
        ? request.from
        : now.subtract(Duration(days: hrDays));
    var t = DateTime.fromMillisecondsSinceEpoch(
      (lower.millisecondsSinceEpoch ~/ 60000) * 60000,
    );
    final stopAt = request.to.isBefore(now) ? request.to : now;
    final today = _midnight(now);
    while (t.isBefore(stopAt)) {
      final minuteOfDay = t.hour * 60 + t.minute;
      final onToday = !t.isBefore(today);
      final partialSkip =
          profile == SimulationProfile.partialDay &&
          (!onToday || minuteOfDay < 360 || minuteOfDay > 720);
      if (!partialSkip) {
        final asleep = minuteOfDay < 390 || minuteOfDay >= 1380;
        final workoutBump = minuteOfDay >= 420 && minuteOfDay < 450 ? 55 : 0;
        final wave = 6 * math.sin(minuteOfDay / 1440 * 2 * math.pi * 3);
        final bpm =
            (asleep ? 56 : 72) +
            wave +
            workoutBump +
            _noise(t.millisecondsSinceEpoch ~/ 60000) * 6;
        final second =
            profile == SimulationProfile.multipleSources && t.minute.isOdd;
        out.add(
          _m(
            'sim-hr-${t.millisecondsSinceEpoch}',
            WearableMetric.heartRate,
            bpm.round(),
            'bpm',
            t,
            t,
            origin: second ? simulatorSecondOrigin : simulatorOrigin,
            device: second ? 'fitness_band' : 'watch',
          ),
        );
      }
      t = t.add(const Duration(minutes: 1));
    }
    return out;
  }

  List<RawMeasurement> _resting(DateTime now, HealthReadRequest request) {
    final out = <RawMeasurement>[];
    for (var i = 0; i < 3; i++) {
      final t = _midnight(
        now,
      ).subtract(Duration(days: i)).add(const Duration(hours: 6));
      if (t.isAfter(now) || t.isBefore(request.from)) continue;
      out.add(
        _m(
          'sim-rhr-${t.millisecondsSinceEpoch}',
          WearableMetric.restingHeartRate,
          58 + (_noise(t.day) * 6).round(),
          'bpm',
          t,
          t,
        ),
      );
    }
    return out;
  }

  List<RawMeasurement> _sleep(DateTime now, HealthReadRequest request) {
    if (profile == SimulationProfile.partialDay) return const [];
    final out = <RawMeasurement>[];
    for (var i = 0; i < 2; i++) {
      final wake = _midnight(
        now,
      ).subtract(Duration(days: i)).add(const Duration(hours: 6, minutes: 30));
      if (wake.isAfter(now) || wake.isBefore(request.from)) continue;
      final hours = profile == SimulationProfile.lowActivityDay ? 5.5 : 7.5;
      final start = wake.subtract(Duration(minutes: (hours * 60).round()));
      out.add(
        _m(
          'sim-sleep-${wake.millisecondsSinceEpoch}',
          WearableMetric.sleep,
          hours * 60,
          'minute',
          start,
          wake,
        ),
      );
      if (profile == SimulationProfile.multipleSources) {
        out.add(
          _m(
            'sim-sleep2-${wake.millisecondsSinceEpoch}',
            WearableMetric.sleep,
            430,
            'minute',
            start.add(const Duration(minutes: 20)),
            wake.subtract(const Duration(minutes: 10)),
            origin: simulatorSecondOrigin,
            device: 'phone',
          ),
        );
      }
      if (profile == SimulationProfile.conflictingSources) {
        out.add(
          _m(
            'sim-sleep3-${wake.millisecondsSinceEpoch}',
            WearableMetric.sleep,
            270,
            'minute',
            start.add(const Duration(hours: 2)),
            wake.subtract(const Duration(hours: 1)),
            origin: simulatorSecondOrigin,
            device: 'phone',
          ),
        );
      }
    }
    return out;
  }

  List<DeviceSession> _workouts(DateTime now, HealthReadRequest request) {
    final out = <DeviceSession>[];
    final today = _midnight(now);
    final morning = today.add(const Duration(hours: 7));
    if (morning.add(const Duration(minutes: 30)).isBefore(now) &&
        profile != SimulationProfile.lowActivityDay &&
        morning.isAfter(request.from)) {
      out.add(
        DeviceSession(
          externalId: 'sim-workout-${morning.millisecondsSinceEpoch}',
          activityType: 'walking',
          startedAt: morning.toUtc(),
          durationMinutes: 30,
          distanceKm: 2.1,
          dataOrigin: simulatorOrigin,
          recordingMethod: 'automatic',
          deviceType: 'watch',
        ),
      );
    }
    final yesterday = today
        .subtract(const Duration(days: 1))
        .add(const Duration(hours: 18));
    if (profile == SimulationProfile.activeDay &&
        yesterday.isAfter(request.from)) {
      out.add(
        DeviceSession(
          externalId: 'sim-workout-${yesterday.millisecondsSinceEpoch}',
          activityType: 'running',
          startedAt: yesterday.toUtc(),
          durationMinutes: 25,
          distanceKm: 4.0,
          dataOrigin: simulatorOrigin,
          recordingMethod: 'automatic',
          deviceType: 'watch',
        ),
      );
    }
    return out;
  }
}
