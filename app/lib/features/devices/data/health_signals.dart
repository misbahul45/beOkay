import 'dart:io';

import 'package:health/health.dart';

import '../../../core/network/account_scoped_repository.dart';
import '../../activity/data/device_activity_source.dart' show validOrigin;

enum SignalType { workouts, steps, weight, glucose, sleep }

extension SignalLabel on SignalType {
  String get wire => name;
  String get label => switch (this) {
    SignalType.workouts => 'Sesi olahraga',
    SignalType.steps => 'Langkah harian',
    SignalType.weight => 'Berat badan',
    SignalType.glucose => 'Glukosa dari alat',
    SignalType.sleep => 'Durasi tidur',
  };
  String get detail => switch (this) {
    SignalType.workouts => 'Sesi dari jam tangan atau aplikasi olahraga',
    SignalType.steps => 'Total langkah per hari untuk tujuan langkah',
    SignalType.weight => 'Dari timbangan pintar atau aplikasi lain',
    SignalType.glucose => 'Dari glukometer yang menulis ke Health Connect',
    SignalType.sleep => 'Jam tidur dan bangun, tanpa tahap tidur',
  };
}

class StepsDay {
  const StepsDay(this.localDate, this.steps);
  final String localDate;
  final int steps;
  Map<String, dynamic> toJson() => {'localDate': localDate, 'steps': steps};
}

class DevicePoint {
  const DevicePoint(
    this.externalId,
    this.from,
    this.to,
    this.value, [
    this.origin,
  ]);
  final String externalId;
  final DateTime from, to;
  final num value;
  final String? origin;
}

abstract interface class HealthSignalsSource {
  Future<bool> available();
  Future<bool> hasAccess(SignalType type);
  Future<bool> requestAccess(SignalType type);
  Future<List<StepsDay>> readSteps(int days);
  Future<List<DevicePoint>> read(SignalType type, DateTime from, DateTime to);
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class HealthConnectSignals implements HealthSignalsSource {
  HealthConnectSignals([Health? health]) : _health = health ?? Health();
  final Health _health;
  bool _configured = false;

  static List<HealthDataType> typesFor(SignalType t) => switch (t) {
    SignalType.workouts => [HealthDataType.WORKOUT],
    SignalType.steps => [HealthDataType.STEPS],
    SignalType.weight => [HealthDataType.WEIGHT],
    SignalType.glucose => [HealthDataType.BLOOD_GLUCOSE],
    SignalType.sleep => [HealthDataType.SLEEP_SESSION],
  };

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  @override
  Future<bool> available() async {
    if (!Platform.isAndroid) return false;
    await _configure();
    return _health.isHealthConnectAvailable();
  }

  @override
  Future<bool> hasAccess(SignalType type) async {
    await _configure();
    final t = typesFor(type);
    return await _health.hasPermissions(
          t,
          permissions: [for (final _ in t) HealthDataAccess.READ],
        ) ==
        true;
  }

  @override
  Future<bool> requestAccess(SignalType type) async {
    await _configure();
    final t = typesFor(type);
    return _health.requestAuthorization(
      t,
      permissions: [for (final _ in t) HealthDataAccess.READ],
    );
  }

  @override
  Future<List<StepsDay>> readSteps(int days) async {
    await _configure();
    final now = DateTime.now();
    final out = <StepsDay>[];
    for (var i = days - 1; i >= 0; i--) {
      final start = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: i));
      final end = i == 0 ? now : start.add(const Duration(days: 1));
      final n = await _health.getTotalStepsInInterval(start, end);
      if (n != null) out.add(StepsDay(isoDate(start), n));
    }
    return out;
  }

  @override
  Future<List<DevicePoint>> read(
    SignalType type,
    DateTime from,
    DateTime to,
  ) async {
    await _configure();
    final points = await _health.getHealthDataFromTypes(
      types: typesFor(type),
      startTime: from,
      endTime: to,
    );
    return [
      for (final p in _health.removeDuplicates(points))
        if (p.value is NumericHealthValue)
          DevicePoint(
            p.uuid,
            p.dateFrom,
            p.dateTo,
            (p.value as NumericHealthValue).numericValue,
            p.sourceId,
          ),
    ];
  }
}

class DeviceImportResult {
  const DeviceImportResult(this.steps, this.weights, this.glucose, this.sleep);
  final int steps, weights, glucose, sleep;
  int get total => steps + weights + glucose + sleep;
}

class DeviceImportRepository extends AccountScopedRepository {
  DeviceImportRepository(super.api, {required super.isCurrentAccount});

  Future<Map<SignalType, bool>> preferences() async {
    final j = (await api.get('/api/me/device-import/preferences')).object;
    return {for (final t in SignalType.values) t: j[t.wire] == true};
  }

  Future<Map<SignalType, bool>> setPreference(SignalType t, bool on) async {
    final j = (await write('PATCH', '/api/me/device-import/preferences', {
      t.wire: on,
    })).object;
    return {for (final t in SignalType.values) t: j[t.wire] == true};
  }

  Future<DeviceImportResult> send({
    List<StepsDay> steps = const [],
    List<DevicePoint> weights = const [],
    List<DevicePoint> glucose = const [],
    List<DevicePoint> sleep = const [],
  }) async {
    var s = 0, w = 0, g = 0, z = 0;
    for (
      var i = 0;
      i <
          [
            steps.length,
            weights.length,
            glucose.length,
            sleep.length,
          ].reduce((a, b) => a > b ? a : b);
      i += 50
    ) {
      List<T> part<T>(List<T> l) => i >= l.length
          ? <T>[]
          : l.sublist(i, i + 50 > l.length ? l.length : i + 50);
      final body = {
        'source': 'health_connect',
        'steps': [for (final x in part(steps)) x.toJson()],
        'weights': [
          for (final x in part(weights))
            {
              'externalId': x.externalId,
              'measuredAt': x.from.toUtc().toIso8601String(),
              'kg': x.value,
              'dataOrigin': ?validOrigin(x.origin),
            },
        ],
        'glucose': [
          for (final x in part(glucose))
            {
              'externalId': x.externalId,
              'measuredAt': x.from.toUtc().toIso8601String(),
              'value': x.value,
              'unit': 'mg/dL',
              'specimen': 'unknown',
              'dataOrigin': ?validOrigin(x.origin),
            },
        ],
        'sleep': [
          for (final x in part(sleep))
            {
              'externalId': x.externalId,
              'startedAt': x.from.toUtc().toIso8601String(),
              'endedAt': x.to.toUtc().toIso8601String(),
              'dataOrigin': ?validOrigin(x.origin),
            },
        ],
      };
      if ((body['steps'] as List).isEmpty &&
          (body['weights'] as List).isEmpty &&
          (body['glucose'] as List).isEmpty &&
          (body['sleep'] as List).isEmpty) {
        continue;
      }
      final r = (await write('POST', '/api/me/device-import', body)).object;
      s += ((r['steps'] as Map)['upserted'] as num).toInt();
      w += ((r['weights'] as Map)['created'] as num).toInt();
      g += ((r['glucose'] as Map)['created'] as num).toInt();
      z += ((r['sleep'] as Map)['created'] as num).toInt();
    }
    return DeviceImportResult(s, w, g, z);
  }
}
