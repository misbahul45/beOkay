import 'dart:io';

import 'package:flutter/services.dart';
import 'package:health/health.dart';

import '../../activity/data/device_activity_source.dart';
import 'health_source.dart';

class MethodChannelDeviceMetadata implements DeviceMetadataBridge {
  const MethodChannelDeviceMetadata();
  static const _channel = MethodChannel('beokay/health_metadata');

  @override
  Future<Map<String, DeviceMetadata>> lookup(
    Set<WearableMetric> metrics,
    DateTime from,
    DateTime to,
  ) async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('lookup', {
        'types': [for (final m in metrics) m.name],
        'start': from.millisecondsSinceEpoch,
        'end': to.millisecondsSinceEpoch,
      });
      if (raw == null) return const {};
      return {
        for (final e in raw.entries)
          if (e.key is String && e.value is Map)
            e.key as String: DeviceMetadata(
              type: _text((e.value as Map)['type']),
              manufacturer: _text((e.value as Map)['manufacturer']),
              model: _text((e.value as Map)['model']),
            ),
      };
    } on MissingPluginException {
      return const {};
    } on PlatformException {
      return const {};
    }
  }

  static String? _text(Object? v) => v is String && v.isNotEmpty ? v : null;
}

class HealthConnectDataSource implements HealthDataSource {
  HealthConnectDataSource({
    Health? health,
    this._metadata = const MethodChannelDeviceMetadata(),
  }) : _health = health ?? Health();

  final Health _health;
  final DeviceMetadataBridge _metadata;
  bool _configured = false;

  @override
  String get sourceKey => 'health_connect';

  @override
  bool get isSimulated => false;

  static List<HealthDataType> typesFor(WearableMetric metric) =>
      switch (metric) {
        WearableMetric.steps => [HealthDataType.STEPS],
        WearableMetric.heartRate => [HealthDataType.HEART_RATE],
        WearableMetric.restingHeartRate => [HealthDataType.RESTING_HEART_RATE],
        WearableMetric.workouts => [HealthDataType.WORKOUT],
        WearableMetric.sleep => [HealthDataType.SLEEP_SESSION],
        WearableMetric.weight => [HealthDataType.WEIGHT],
        WearableMetric.glucose => [HealthDataType.BLOOD_GLUCOSE],
      };

  static List<HealthDataType> permissionTypesFor(WearableMetric metric) =>
      metric == WearableMetric.workouts
      ? [
          HealthDataType.WORKOUT,
          HealthDataType.STEPS,
          HealthDataType.DISTANCE_DELTA,
          HealthDataType.TOTAL_CALORIES_BURNED,
        ]
      : typesFor(metric);

  static String? _originOf(HealthDataPoint p) {
    if (p.sourceName.isNotEmpty) return p.sourceName;
    return p.sourceId.isNotEmpty ? p.sourceId : null;
  }

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  @override
  Future<SourceCapabilities> capabilities() async {
    if (!Platform.isAndroid) {
      return const SourceCapabilities(
        platform: HealthPlatformState.unsupportedPlatform,
      );
    }
    try {
      await _configure();
      final status = await _health.getHealthConnectSdkStatus();
      if (status ==
          HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired) {
        return const SourceCapabilities(
          platform: HealthPlatformState.installRequired,
        );
      }
      if (status != HealthConnectSdkStatus.sdkAvailable) {
        return const SourceCapabilities(
          platform: HealthPlatformState.healthConnectUnavailable,
        );
      }
      return SourceCapabilities(
        platform: HealthPlatformState.available,
        backgroundRead: await _health.isHealthDataInBackgroundAvailable(),
        historyRead: await _health.isHealthDataHistoryAvailable(),
      );
    } catch (_) {
      return const SourceCapabilities(
        platform: HealthPlatformState.healthConnectUnavailable,
      );
    }
  }

  @override
  Future<bool> hasAccess(WearableMetric metric) async {
    await _configure();
    final types = permissionTypesFor(metric);
    return await _health.hasPermissions(
          types,
          permissions: [for (final _ in types) HealthDataAccess.READ],
        ) ==
        true;
  }

  @override
  Future<bool> requestAccess(WearableMetric metric) async {
    await _configure();
    final types = permissionTypesFor(metric);
    return _health.requestAuthorization(
      types,
      permissions: [for (final _ in types) HealthDataAccess.READ],
    );
  }

  @override
  Future<HealthReadResult> read(HealthReadRequest request) async {
    await _configure();
    final measurements = <RawMeasurement>[];
    final workouts = <DeviceSession>[];
    final errors = <WearableMetric, String>{};
    final sampled = request.metrics.intersection({
      WearableMetric.heartRate,
      WearableMetric.restingHeartRate,
      WearableMetric.sleep,
      WearableMetric.workouts,
      WearableMetric.weight,
      WearableMetric.glucose,
    });
    final meta = sampled.isEmpty
        ? const <String, DeviceMetadata>{}
        : await _metadata.lookup(sampled, request.from, request.to);
    for (final metric in request.metrics) {
      try {
        switch (metric) {
          case WearableMetric.steps:
            measurements.addAll(await _readSteps(request.stepsDays));
          case WearableMetric.workouts:
            workouts.addAll(await _readWorkouts(request, meta));
          default:
            measurements.addAll(await _readPoints(metric, request, meta));
        }
      } catch (_) {
        errors[metric] = 'READ_FAILED';
      }
    }
    return HealthReadResult(
      measurements: measurements,
      workouts: workouts,
      errors: errors,
    );
  }

  Future<List<RawMeasurement>> _readSteps(int days) async {
    final now = DateTime.now();
    final out = <RawMeasurement>[];
    for (var i = days - 1; i >= 0; i--) {
      final start = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: i));
      final end = i == 0 ? now : start.add(const Duration(days: 1));
      final total = await _health.getTotalStepsInInterval(
        start,
        end,
        includeManualEntry: false,
      );
      if (total == null) continue;
      out.add(
        RawMeasurement(
          id: 'steps:${start.millisecondsSinceEpoch}',
          metric: WearableMetric.steps,
          value: total,
          unit: 'count',
          startTime: start,
          endTime: end,
        ),
      );
    }
    return out;
  }

  Future<List<RawMeasurement>> _readPoints(
    WearableMetric metric,
    HealthReadRequest request,
    Map<String, DeviceMetadata> meta,
  ) async {
    final points = await _health.getHealthDataFromTypes(
      types: typesFor(metric),
      startTime: request.from,
      endTime: request.to,
    );
    final unit = switch (metric) {
      WearableMetric.heartRate || WearableMetric.restingHeartRate => 'bpm',
      WearableMetric.sleep => 'minute',
      WearableMetric.weight => 'kg',
      WearableMetric.glucose => 'mg/dL',
      _ => 'count',
    };
    final out = <RawMeasurement>[];
    for (final p in _health.removeDuplicates(points)) {
      final v = p.value;
      if (v is! NumericHealthValue) continue;
      final m = meta[p.uuid];
      out.add(
        RawMeasurement(
          id: p.uuid,
          metric: metric,
          value: metric == WearableMetric.sleep
              ? p.dateTo.difference(p.dateFrom).inSeconds / 60
              : v.numericValue,
          unit: unit,
          startTime: p.dateFrom,
          endTime: p.dateTo,
          origin: _originOf(p),
          recordingMethod: p.recordingMethod.name,
          deviceType: m?.type,
          deviceManufacturer: m?.manufacturer,
          deviceModel: m?.model,
        ),
      );
    }
    return out;
  }

  Future<List<DeviceSession>> _readWorkouts(
    HealthReadRequest request,
    Map<String, DeviceMetadata> meta,
  ) async {
    final points = await _health.getHealthDataFromTypes(
      types: typesFor(WearableMetric.workouts),
      startTime: request.from,
      endTime: request.to,
    );
    final out = <DeviceSession>[];
    for (final p in _health.removeDuplicates(points)) {
      final v = p.value;
      if (v is! WorkoutHealthValue) continue;
      final minutes = durationMinutesFrom(p.dateFrom, p.dateTo);
      if (minutes == null) continue;
      out.add(
        DeviceSession(
          externalId: p.uuid,
          activityType: mapWorkoutType(v.workoutActivityType.name),
          startedAt: p.dateFrom.toUtc(),
          durationMinutes: minutes,
          distanceKm: distanceKmFrom(
            v.totalDistance,
            v.totalDistanceUnit?.name,
          ),
          steps: v.totalStepsUnit?.name == 'COUNT' ? v.totalSteps : null,
          dataOrigin: _originOf(p),
          recordingMethod: p.recordingMethod.name,
          deviceType: meta[p.uuid]?.type,
        ),
      );
    }
    return out;
  }
}

Future<bool> openHealthConnectSettings() async {
  try {
    return await MethodChannelDeviceMetadata._channel.invokeMethod<bool>(
          'openSettings',
        ) ??
        false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}
