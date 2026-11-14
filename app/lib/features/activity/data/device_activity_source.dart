import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/account_scoped_repository.dart';
import '../../devices/data/health_connect_source.dart';
import '../../devices/data/health_source.dart';

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
    this.deviceType,
  });
  final String externalId, activityType;
  final DateTime startedAt;
  final int durationMinutes;
  final double? distanceKm;
  final int? steps;
  final String? dataOrigin;
  final String? recordingMethod;
  final String? deviceType;

  Map<String, dynamic> toJson() => {
    'externalId': externalId,
    'activityType': activityType,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'durationMinutes': durationMinutes,
    'distanceKm': ?distanceKm,
    'steps': ?steps,
    'dataOrigin': ?validOrigin(dataOrigin),
    'recordingMethod': ?recordingMethod,
    'device': ?deviceType,
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

class HealthConnectSource implements DeviceActivitySource {
  HealthConnectSource([HealthDataSource? source])
    : _source = source ?? HealthConnectDataSource();
  final HealthDataSource _source;

  @override
  String get sourceKey => _source.sourceKey;
  @override
  String get displayName => 'Health Connect';

  @override
  Future<DeviceSourceStatus> status() async {
    final caps = await _source.capabilities();
    return switch (caps.platform) {
      HealthPlatformState.unsupportedPlatform =>
        DeviceSourceStatus.unsupportedPlatform,
      HealthPlatformState.healthConnectUnavailable ||
      HealthPlatformState.installRequired => DeviceSourceStatus.notInstalled,
      HealthPlatformState.available =>
        await _source.hasAccess(WearableMetric.workouts)
            ? DeviceSourceStatus.ready
            : DeviceSourceStatus.needsPermission,
    };
  }

  @override
  Future<bool> requestAccess() =>
      _source.requestAccess(WearableMetric.workouts);

  @override
  Future<List<DeviceSession>> readWorkouts({
    required DateTime from,
    required DateTime to,
  }) async => (await _source.read(
    HealthReadRequest(
      metrics: const {WearableMetric.workouts},
      from: from,
      to: to,
    ),
  )).workouts;
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
