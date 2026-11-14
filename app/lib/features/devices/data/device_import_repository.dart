import '../../../core/network/account_scoped_repository.dart';
import '../domain/device_status.dart';
import 'health_source.dart';

class MetricResult {
  const MetricResult({
    this.created = 0,
    this.updated = 0,
    this.duplicate = 0,
    this.unchanged = 0,
    this.rejected = 0,
    this.needsReview = 0,
  });
  final int created, updated, duplicate, unchanged, rejected, needsReview;

  MetricResult operator +(MetricResult o) => MetricResult(
    created: created + o.created,
    updated: updated + o.updated,
    duplicate: duplicate + o.duplicate,
    unchanged: unchanged + o.unchanged,
    rejected: rejected + o.rejected,
    needsReview: needsReview + o.needsReview,
  );

  int get imported => created + updated;
  int get total => imported + duplicate + unchanged + rejected;

  static MetricResult fromDomain(Map<String, dynamic> j) => MetricResult(
    created: (j['created'] as num?)?.toInt() ?? 0,
    updated: (j['updated'] as num?)?.toInt() ?? 0,
    duplicate: (j['duplicate'] as num?)?.toInt() ?? 0,
    unchanged: (j['unchanged'] as num?)?.toInt() ?? 0,
    rejected: (j['rejected'] as num?)?.toInt() ?? 0,
    needsReview: (j['needsReview'] as num?)?.toInt() ?? 0,
  );
}

const batchLimits = <WearableMetric, int>{
  WearableMetric.steps: 30,
  WearableMetric.heartRate: 150,
  WearableMetric.restingHeartRate: 50,
  WearableMetric.sleep: 50,
  WearableMetric.weight: 100,
  WearableMetric.glucose: 100,
  WearableMetric.workouts: 100,
};

class DeviceImportRepository extends AccountScopedRepository {
  DeviceImportRepository(super.api, {required super.isCurrentAccount});

  Future<Map<WearableMetric, bool>> preferences() async {
    final j = (await api.get('/api/me/device-import/preferences')).object;
    return {for (final m in WearableMetric.values) m: j[m.prefKey] == true};
  }

  Future<Map<WearableMetric, bool>> setPreferences(
    Map<WearableMetric, bool> changes,
  ) async {
    final j = (await write('PATCH', '/api/me/device-import/preferences', {
      for (final e in changes.entries) e.key.prefKey: e.value,
    })).object;
    return {for (final m in WearableMetric.values) m: j[m.prefKey] == true};
  }

  Future<Map<WearableMetric, bool>> setPreference(
    WearableMetric metric,
    bool on,
  ) => setPreferences({metric: on});

  Future<MetricResult> sendMetric(
    String source,
    WearableMetric metric,
    List<Map<String, dynamic>> items,
  ) async {
    if (items.isEmpty) return const MetricResult();
    if (metric == WearableMetric.workouts) {
      final r =
          (await write('POST', '/api/me/activities/import', {
                'source': source,
                'sessions': items,
              })).object['summary']
              as Map<String, dynamic>;
      return MetricResult(
        created: (r['created'] as num).toInt(),
        needsReview: (r['createdNeedsReview'] as num).toInt(),
        duplicate: (r['duplicate'] as num).toInt(),
        rejected: (r['rejected'] as num).toInt(),
      );
    }
    final key = switch (metric) {
      WearableMetric.steps => 'steps',
      WearableMetric.heartRate => 'heartRate',
      WearableMetric.restingHeartRate => 'restingHeartRate',
      WearableMetric.sleep => 'sleep',
      WearableMetric.weight => 'weights',
      WearableMetric.glucose => 'glucose',
      WearableMetric.workouts => 'workouts',
    };
    final r = (await write('POST', '/api/me/device-import', {
      'source': source,
      key: items,
    })).object;
    final domain = r[key] as Map<String, dynamic>? ?? const {};
    if (metric == WearableMetric.steps) {
      return MetricResult(
        created: (domain['upserted'] as num?)?.toInt() ?? 0,
        unchanged: (domain['unchanged'] as num?)?.toInt() ?? 0,
        rejected: (domain['rejected'] as num?)?.toInt() ?? 0,
      );
    }
    return MetricResult.fromDomain(domain);
  }

  Future<void> reportCheckpoint(
    String source,
    WearableMetric metric,
    String outcome, {
    String? errorCode,
    String? cursor,
  }) async {
    await write('PUT', '/api/me/device-sync/checkpoints', {
      'source': source,
      'metric': metric.checkpointKey,
      'outcome': outcome,
      'errorCode': ?errorCode,
      'cursor': ?cursor,
    });
  }

  Future<DeviceStatus> status() async =>
      DeviceStatus.fromJson((await api.get('/api/me/devices/status')).object);
}
