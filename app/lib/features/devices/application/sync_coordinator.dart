import 'dart:async';
import 'dart:math' as math;

import '../../../core/network/api_exception.dart';
import '../data/device_import_repository.dart';
import '../data/health_source.dart';
import '../domain/normalizer.dart';
import 'sync_store.dart';

enum SyncTrigger {
  initialConnection,
  manual,
  resume,
  periodic,
  background,
  networkRestored,
}

class MetricSyncOutcome {
  const MetricSyncOutcome({
    required this.metric,
    this.result = const MetricResult(),
    this.errorCode,
    this.read = 0,
    this.skippedReason,
  });
  final WearableMetric metric;
  final MetricResult result;
  final String? errorCode;
  final int read;
  final String? skippedReason;
  bool get failed => errorCode != null;
}

class SyncReport {
  const SyncReport({
    required this.at,
    this.outcomes = const {},
    this.blockedBy,
    this.rejectedLocally = 0,
    this.sleepConflicts = 0,
    this.drainedFromOutbox = 0,
    this.outboxDropped = 0,
    this.simulated = false,
  });
  final DateTime at;
  final Map<WearableMetric, MetricSyncOutcome> outcomes;
  final String? blockedBy;
  final int rejectedLocally, sleepConflicts, drainedFromOutbox, outboxDropped;
  final bool simulated;

  MetricResult get totals =>
      outcomes.values.fold(const MetricResult(), (a, o) => a + o.result);
  bool get hasFailure =>
      blockedBy != null || outcomes.values.any((o) => o.failed);
  String? get firstError =>
      blockedBy ??
      outcomes.values.where((o) => o.failed).firstOrNull?.errorCode;
}

class _Stop implements Exception {
  const _Stop(this.code);
  final String code;
}

class SyncCoordinator {
  SyncCoordinator({
    required this.source,
    required this.repo,
    required this.store,
    HealthNormalizer? normalizer,
    DateTime Function()? clock,
    bool Function()? isCurrentAccount,
  }) : _normalizer = normalizer ?? HealthNormalizer(clock: clock),
       _clock = clock ?? DateTime.now,
       _current = isCurrentAccount ?? (() => true);

  final HealthDataSource source;
  final DeviceImportRepository repo;
  final SyncStore store;
  final HealthNormalizer _normalizer;
  final DateTime Function() _clock;
  final bool Function() _current;
  Future<SyncReport>? _running;

  bool get running => _running != null;

  Future<SyncReport> sync({
    required Set<WearableMetric> enabled,
    SyncTrigger trigger = SyncTrigger.manual,
  }) {
    final active = _running;
    if (active != null) return active;
    late final Future<SyncReport> run;
    run = _run(enabled, trigger).whenComplete(() {
      if (identical(_running, run)) _running = null;
    });
    _running = run;
    return run;
  }

  Future<void> _fail(WearableMetric m, String code) async {
    try {
      await repo.reportCheckpoint(
        source.sourceKey,
        m,
        'failure',
        errorCode: code,
      );
    } catch (_) {}
  }

  Future<SyncReport> _run(
    Set<WearableMetric> enabled,
    SyncTrigger trigger,
  ) async {
    final at = _clock();
    final key = source.sourceKey;
    SyncReport blocked(
      String code, [
      Map<WearableMetric, MetricSyncOutcome>? o,
    ]) => SyncReport(
      at: at,
      outcomes: o ?? const {},
      blockedBy: code,
      simulated: source.isSimulated,
    );
    if (!_current()) return blocked('ACCOUNT_CHANGED');
    if (enabled.isEmpty) return blocked('IMPORT_DISABLED');

    final caps = await source.capabilities();
    if (!caps.available) {
      final code = switch (caps.platform) {
        HealthPlatformState.unsupportedPlatform => 'PLATFORM_UNSUPPORTED',
        HealthPlatformState.installRequired =>
          'HEALTH_CONNECT_INSTALL_REQUIRED',
        _ => 'HEALTH_CONNECT_UNAVAILABLE',
      };
      for (final m in enabled) {
        await _fail(m, code);
      }
      return blocked(code);
    }

    final outcomes = <WearableMetric, MetricSyncOutcome>{};
    final granted = <WearableMetric>{};
    for (final m in enabled) {
      if (await source.hasAccess(m)) {
        granted.add(m);
      } else {
        final had = await store.cursor(key, m) != null;
        final code = had ? 'PERMISSION_REVOKED' : 'PERMISSION_DENIED';
        outcomes[m] = MetricSyncOutcome(metric: m, errorCode: code);
        await _fail(m, code);
      }
    }
    if (granted.isEmpty) {
      return SyncReport(
        at: at,
        outcomes: outcomes,
        simulated: source.isSimulated,
      );
    }

    final drain = await _drain();
    if (drain.blocked != null) {
      return SyncReport(
        at: at,
        outcomes: outcomes,
        blockedBy: drain.blocked,
        drainedFromOutbox: drain.drained,
        simulated: source.isSimulated,
      );
    }

    final window = await _window(granted, trigger, at);
    HealthReadResult read;
    try {
      read = await source.read(
        HealthReadRequest(
          metrics: granted,
          from: window.from,
          to: at,
          stepsDays: window.stepsDays,
        ),
      );
    } catch (_) {
      for (final m in granted) {
        outcomes[m] = MetricSyncOutcome(metric: m, errorCode: 'READ_FAILED');
        await _fail(m, 'READ_FAILED');
      }
      return SyncReport(
        at: at,
        outcomes: outcomes,
        simulated: source.isSimulated,
      );
    }
    final live = {...granted};
    for (final e in read.errors.entries) {
      outcomes[e.key] = MetricSyncOutcome(metric: e.key, errorCode: e.value);
      live.remove(e.key);
      await _fail(e.key, e.value);
    }

    final batch = _normalizer.normalize(read);
    final payloads = <WearableMetric, List<Map<String, dynamic>>>{
      WearableMetric.steps: [for (final x in batch.steps) x.toJson()],
      WearableMetric.heartRate: [for (final x in batch.heartRate) x.toJson()],
      WearableMetric.restingHeartRate: [
        for (final x in batch.resting) x.toJson(),
      ],
      WearableMetric.sleep: [for (final x in batch.sleep) x.toJson()],
      WearableMetric.weight: [for (final x in batch.weights) x.toJson()],
      WearableMetric.glucose: [for (final x in batch.glucose) x.toJson()],
      WearableMetric.workouts: [for (final x in batch.workouts) x.toJson()],
    };

    var dropped = 0;
    String? stop;
    for (final m in WearableMetric.values) {
      if (!live.contains(m) || stop != null) continue;
      final items = payloads[m]!;
      if (source.isSimulated && m.sensitive) {
        outcomes[m] = MetricSyncOutcome(
          metric: m,
          read: items.length,
          skippedReason: 'SIMULATED_NOT_SENT',
        );
        continue;
      }
      var result = const MetricResult();
      try {
        final limit = batchLimits[m]!;
        for (var i = 0; i < items.length; i += limit) {
          if (!_current()) throw const _Stop('ACCOUNT_CHANGED');
          final chunk = items.sublist(i, math.min(i + limit, items.length));
          try {
            result = result + await repo.sendMetric(key, m, chunk);
          } on ApiException catch (e) {
            if (e.isNetwork) {
              for (var j = i; j < items.length; j += limit) {
                dropped += await store.enqueue(
                  OutboxEntry(
                    id: '${at.microsecondsSinceEpoch}-${m.name}-$j',
                    source: key,
                    metric: m,
                    items: items.sublist(j, math.min(j + limit, items.length)),
                    createdAt: at,
                  ),
                );
              }
            }
            rethrow;
          }
        }
        await store.setCursor(key, m, at);
        try {
          await repo.reportCheckpoint(
            key,
            m,
            'success',
            cursor: at.toUtc().toIso8601String(),
          );
        } catch (_) {}
        outcomes[m] = MetricSyncOutcome(
          metric: m,
          result: result,
          read: items.length,
        );
      } on _Stop catch (s) {
        stop = s.code;
      } on ApiException catch (e) {
        final code = _codeFor(e);
        outcomes[m] = MetricSyncOutcome(
          metric: m,
          result: result,
          errorCode: code,
          read: items.length,
        );
        if (code == 'CONSENT_REQUIRED') {
          await store.clearOutbox();
          stop = code;
        } else if (code == 'UNAUTHENTICATED') {
          stop = code;
        } else {
          await _fail(m, code);
        }
      }
    }

    return SyncReport(
      at: at,
      outcomes: outcomes,
      blockedBy: stop,
      rejectedLocally: batch.rejectedTotal,
      sleepConflicts: batch.sleepConflicts,
      drainedFromOutbox: drain.drained,
      outboxDropped: dropped,
      simulated: source.isSimulated,
    );
  }

  String _codeFor(ApiException e) {
    if (e.isNetwork) return 'NETWORK_UNAVAILABLE';
    if (e.status == 401) return 'UNAUTHENTICATED';
    if (e.status == 403 && e.code == 'CONSENT_REQUIRED') {
      return 'CONSENT_REQUIRED';
    }
    if (e.status == 403 && e.code == 'SIMULATION_DISABLED') {
      return 'SIMULATION_DISABLED';
    }
    if (e.status == 429) return 'RATE_LIMITED';
    if (e.status == 400) return 'VALIDATION_ERROR';
    return 'SERVER_ERROR';
  }

  Future<({DateTime from, int stepsDays})> _window(
    Set<WearableMetric> granted,
    SyncTrigger trigger,
    DateTime at,
  ) async {
    final full = at.subtract(const Duration(days: 14));
    final fullWindow = (from: full, stepsDays: 14);
    if (trigger == SyncTrigger.manual ||
        trigger == SyncTrigger.initialConnection) {
      return fullWindow;
    }
    DateTime? oldest;
    for (final m in granted) {
      final c = await store.cursor(source.sourceKey, m);
      if (c == null) return fullWindow;
      if (oldest == null || c.isBefore(oldest)) oldest = c;
    }
    if (oldest == null) return fullWindow;
    var from = oldest.subtract(const Duration(hours: 24));
    if (from.isBefore(full)) from = full;
    final aligned = DateTime.fromMillisecondsSinceEpoch(
      (from.millisecondsSinceEpoch ~/ bucketMillis) * bucketMillis,
    );
    final days = (at.difference(oldest).inDays + 3).clamp(3, 14);
    return (from: aligned, stepsDays: days);
  }

  Future<({int drained, String? blocked})> _drain() async {
    final entries = await store.outbox();
    if (entries.isEmpty) return (drained: 0, blocked: null);
    final keep = <OutboxEntry>[];
    var drained = 0;
    String? blocked;
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (blocked != null) {
        keep.add(e);
        continue;
      }
      try {
        await repo.sendMetric(e.source, e.metric, e.items);
        drained++;
      } on ApiException catch (x) {
        if (x.isNetwork || x.status == 401) {
          keep.addAll(entries.sublist(i));
          blocked = x.isNetwork ? 'NETWORK_UNAVAILABLE' : 'UNAUTHENTICATED';
          break;
        }
        if (x.status == 403 && x.code == 'CONSENT_REQUIRED') {
          await store.clearOutbox();
          return (drained: drained, blocked: 'CONSENT_REQUIRED');
        }
        final next = e.bumped();
        if (x.status >= 500 && next.attempts < SyncStore.maxOutboxAttempts) {
          keep.add(next);
        }
      }
    }
    await store.saveOutbox(keep);
    return (drained: drained, blocked: blocked);
  }
}
