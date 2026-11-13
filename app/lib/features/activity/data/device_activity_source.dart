import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart';

import '../../../core/network/account_scoped_repository.dart';

/// Satu sesi olahraga dari perangkat, sudah dipetakan ke bentuk beOkay. Jarak/langkah kosong bila tidak jelas.
final _originPattern = RegExp(r'^[A-Za-z0-9_.]{1,200}$');

String? validOrigin(String? origin) =>
    origin != null && _originPattern.hasMatch(origin) ? origin : null;

class DeviceSession {
  const DeviceSession({
    required this.externalId,
    required this.activityType,
    required this.startedAt,
    required this.durationMinutes,
    this.distanceKm,
    this.steps,
    this.dataOrigin,
    this.recordingMethod,
  });
  final String externalId, activityType;
  final DateTime startedAt;
  final int durationMinutes;
  final double? distanceKm;
  final int? steps;
  final String? dataOrigin;
  final String? recordingMethod;

  Map<String, dynamic> toJson() => {
    'externalId': externalId,
    'activityType': activityType,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'durationMinutes': durationMinutes,
    'distanceKm': ?distanceKm,
    'steps': ?steps,
    'dataOrigin': ?validOrigin(dataOrigin),
    'recordingMethod': ?recordingMethod,
  };
}

enum DeviceSourceStatus {
  unsupportedPlatform,
  notInstalled,
  needsPermission,
  ready,
}

abstract interface class DeviceActivitySource {
  String get sourceKey; // dikirim ke server: health_connect
  String get displayName;
  Future<DeviceSourceStatus> status();
  Future<bool> requestAccess();
  Future<List<DeviceSession>> readWorkouts({
    required DateTime from,
    required DateTime to,
  });
}

/// Pemetaan jenis olahraga. Yang tidak dikenal menjadi "other" (tidak ditebak).
String mapWorkoutType(String name) => switch (name) {
  'WALKING' || 'WALKING_TREADMILL' => 'walking',
  'RUNNING' || 'RUNNING_TREADMILL' => 'running',
  'BIKING' || 'BIKING_STATIONARY' => 'cycling',
  'STRENGTH_TRAINING' || 'TRADITIONAL_STRENGTH_TRAINING' => 'strength',
  _ => 'other',
};

/// Meter → km hanya bila satuannya jelas meter; selain itu null.
double? distanceKmFrom(num? value, String? unitName) {
  if (value == null || unitName != 'METER' || value < 0) return null;
  return (value / 1000 * 1000).round() / 1000;
}

/// Durasi menit penuh, minimal 1, ditolak bila di luar 1..1440.
int? durationMinutesFrom(DateTime from, DateTime to) {
  final m = to.difference(from).inSeconds / 60;
  if (m < 0.5) return null;
  final rounded = m.round().clamp(1, 100000);
  return rounded > 1440 ? null : rounded;
}

/// Health Connect (Android) lewat paket `health`. iOS/HealthKit sengaja tidak didukung: belum dikonfigurasi/diverifikasi.
class HealthConnectSource implements DeviceActivitySource {
  HealthConnectSource([Health? health]) : _health = health ?? Health();
  final Health _health;
  bool _configured = false;
  static const _types = [HealthDataType.WORKOUT];
  static const _access = [HealthDataAccess.READ];

  @override
  String get sourceKey => 'health_connect';
  @override
  String get displayName => 'Health Connect';

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  @override
  Future<DeviceSourceStatus> status() async {
    if (!Platform.isAndroid) return DeviceSourceStatus.unsupportedPlatform;
    await _configure();
    if (!await _health.isHealthConnectAvailable()) {
      return DeviceSourceStatus.notInstalled;
    }
    final granted = await _health.hasPermissions(_types, permissions: _access);
    return granted == true
        ? DeviceSourceStatus.ready
        : DeviceSourceStatus.needsPermission;
  }

  @override
  Future<bool> requestAccess() async {
    await _configure();
    return _health.requestAuthorization(_types, permissions: _access);
  }

  @override
  Future<List<DeviceSession>> readWorkouts({
    required DateTime from,
    required DateTime to,
  }) async {
    await _configure();
    final points = await _health.getHealthDataFromTypes(
      types: _types,
      startTime: from,
      endTime: to,
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
          dataOrigin: p.sourceId,
          recordingMethod: p.recordingMethod.name,
        ),
      );
    }
    return out;
  }
}

/// Null di platform yang tidak didukung (juga di tes) sehingga bagian impor disembunyikan.
final deviceActivitySourceProvider = Provider<DeviceActivitySource?>(
  (ref) => Platform.isAndroid ? HealthConnectSource() : null,
);

class ImportSummary {
  const ImportSummary({
    required this.created,
    required this.needsReview,
    required this.duplicate,
    required this.rejected,
    required this.read,
  });
  final int created, needsReview, duplicate, rejected, read;
}

class ActivityImportRepository extends AccountScopedRepository {
  ActivityImportRepository(super.api, {required super.isCurrentAccount});

  /// Mengirim dalam kelompok ≤100 sesi. Server idempoten per (sumber, externalId), jadi aman diulang.
  Future<ImportSummary> send(
    String source,
    List<DeviceSession> sessions,
  ) async {
    var created = 0, review = 0, dup = 0, rejected = 0;
    for (var i = 0; i < sessions.length; i += 100) {
      final batch = sessions.sublist(
        i,
        i + 100 > sessions.length ? sessions.length : i + 100,
      );
      final r =
          (await write('POST', '/api/me/activities/import', {
                'source': source,
                'sessions': [for (final s in batch) s.toJson()],
              })).object['summary']
              as Map<String, dynamic>;
      created += (r['created'] as num).toInt();
      review += (r['createdNeedsReview'] as num).toInt();
      dup += (r['duplicate'] as num).toInt();
      rejected += (r['rejected'] as num).toInt();
    }
    return ImportSummary(
      created: created,
      needsReview: review,
      duplicate: dup,
      rejected: rejected,
      read: sessions.length,
    );
  }
}
