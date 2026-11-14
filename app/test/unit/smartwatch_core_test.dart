import 'dart:convert';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/offline/offline_queue.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/features/activity/data/device_activity_source.dart';
import 'package:app/features/devices/application/sync_coordinator.dart';
import 'package:app/features/devices/application/sync_store.dart';
import 'package:app/features/devices/data/device_import_repository.dart';
import 'package:app/features/devices/data/health_source.dart';
import 'package:app/features/devices/data/simulated_source.dart';
import 'package:app/features/devices/domain/connection_state.dart';
import 'package:app/features/devices/domain/normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _now = DateTime(2026, 11, 14, 14, 30);

RawMeasurement _hr(
  DateTime t,
  num bpm, {
  String? origin = 'a.b',
  String? device,
}) => RawMeasurement(
  id: 'hr-${t.millisecondsSinceEpoch}',
  metric: WearableMetric.heartRate,
  value: bpm,
  unit: 'bpm',
  startTime: t,
  endTime: t,
  origin: origin,
  recordingMethod: 'automatic',
  deviceType: device,
);

class _Spy implements HealthDataSource {
  _Spy(this.inner);
  final SimulatedHealthDataSource inner;
  final requests = <HealthReadRequest>[];
  @override
  String get sourceKey => inner.sourceKey;
  @override
  bool get isSimulated => inner.isSimulated;
  @override
  Future<SourceCapabilities> capabilities() => inner.capabilities();
  @override
  Future<bool> hasAccess(WearableMetric metric) => inner.hasAccess(metric);
  @override
  Future<bool> requestAccess(WearableMetric metric) =>
      inner.requestAccess(metric);
  @override
  Future<HealthReadResult> read(HealthReadRequest request) {
    requests.add(request);
    return inner.read(request);
  }
}

class _Unavailable implements HealthDataSource {
  _Unavailable(this.platform);
  final HealthPlatformState platform;
  @override
  String get sourceKey => 'health_connect';
  @override
  bool get isSimulated => false;
  @override
  Future<SourceCapabilities> capabilities() async =>
      SourceCapabilities(platform: platform);
  @override
  Future<bool> hasAccess(WearableMetric metric) async => false;
  @override
  Future<bool> requestAccess(WearableMetric metric) async => false;
  @override
  Future<HealthReadResult> read(HealthReadRequest request) async =>
      const HealthReadResult();
}

class _Env {
  _Env({this.handler}) {
    final tokens = MemoryTokenStorage()..write('t');
    repo = DeviceImportRepository(
      ApiClient(
        tokens: tokens,
        baseUrl: 'http://test',
        client: MockClient((r) async {
          seen.add(r);
          final custom = handler?.call(r);
          if (custom != null) return custom;
          return _serverOk(r);
        }),
      ),
      isCurrentAccount: () => accountOk,
    );
    store = SyncStore(kv, 'u1');
  }

  final http.Response? Function(http.Request r)? handler;
  final seen = <http.Request>[];
  final kv = MemoryKeyValueStore();
  bool accountOk = true;
  late final DeviceImportRepository repo;
  late final SyncStore store;

  SyncCoordinator coordinator(
    HealthDataSource source, {
    bool Function()? current,
  }) => SyncCoordinator(
    source: source,
    repo: repo,
    store: store,
    clock: () => _now,
    isCurrentAccount: current ?? () => accountOk,
  );

  List<http.Request> posts(String path) =>
      seen.where((r) => r.method == 'POST' && r.url.path == path).toList();

  List<http.Request> checkpoints() => seen
      .where(
        (r) =>
            r.method == 'PUT' &&
            r.url.path == '/api/me/device-sync/checkpoints',
      )
      .toList();
}

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

http.Response _serverOk(http.Request r) {
  if (r.url.path == '/api/me/device-sync/checkpoints') return _json({});
  if (r.url.path == '/api/me/activities/import') {
    final n = ((jsonDecode(r.body) as Map)['sessions'] as List).length;
    return _json({
      'summary': {
        'created': n,
        'createdNeedsReview': 0,
        'duplicate': 0,
        'rejected': 0,
      },
    });
  }
  final body = jsonDecode(r.body) as Map<String, dynamic>;
  final out = <String, dynamic>{};
  for (final k in [
    'steps',
    'heartRate',
    'restingHeartRate',
    'sleep',
    'weights',
    'glucose',
  ]) {
    final list = body[k];
    if (list is! List) continue;
    out[k] = k == 'steps'
        ? {'upserted': list.length, 'unchanged': 0, 'rejected': 0}
        : {
            'created': list.length,
            'updated': 0,
            'duplicate': 0,
            'unchanged': 0,
            'rejected': 0,
            'needsReview': 0,
          };
  }
  return _json(out);
}

http.Response _error(int status, String code) => _json({
  'error': {'code': code, 'message': 'x'},
}, status);

Future<SimulatedHealthDataSource> _granted({
  SimulationProfile profile = SimulationProfile.activeDay,
  Iterable<WearableMetric> metrics = const [
    WearableMetric.steps,
    WearableMetric.heartRate,
    WearableMetric.restingHeartRate,
    WearableMetric.sleep,
    WearableMetric.workouts,
  ],
}) async {
  final s = SimulatedHealthDataSource(
    profile: profile,
    clock: () => _now,
    includeCompatibilityFixtures: true,
  );
  for (final m in metrics) {
    await s.requestAccess(m);
  }
  return s;
}

void main() {
  group('normalizer', () {
    final normalizer = HealthNormalizer(clock: () => _now);

    test(
      'sampel dikelompokkan per 5 menit dengan min, maks, rata-rata dan jumlah sampel',
      () {
        final base = DateTime.utc(2026, 11, 14, 3, 0);
        final batch = normalizer.normalize(
          HealthReadResult(
            measurements: [
              _hr(base, 60),
              _hr(base.add(const Duration(minutes: 1)), 70),
              _hr(base.add(const Duration(minutes: 4)), 80),
              _hr(base.add(const Duration(minutes: 6)), 90),
            ],
          ),
        );
        expect(batch.heartRate, hasLength(2));
        final first = batch.heartRate.first;
        expect([first.min, first.max, first.count], [60, 80, 3]);
        expect(first.avg, 70);
        expect(first.bucketStart.millisecondsSinceEpoch % bucketMillis, 0);
        expect(batch.heartRate.last.count, 1);
      },
    );

    test(
      'asal data berbeda tidak digabung dan metadata perangkat dipertahankan',
      () {
        final t = DateTime.utc(2026, 11, 14, 3, 0);
        final batch = normalizer.normalize(
          HealthReadResult(
            measurements: [
              _hr(t, 60, origin: 'x.one', device: 'watch'),
              _hr(
                t.add(const Duration(minutes: 1)),
                62,
                origin: 'x.two',
                device: 'phone',
              ),
              _hr(t.add(const Duration(minutes: 2)), 64, origin: null),
            ],
          ),
        );
        expect(
          batch.heartRate.map((b) => b.origin),
          unorderedEquals(['x.one', 'x.two', null]),
        );
        expect(
          batch.heartRate.firstWhere((b) => b.origin == 'x.one').deviceType,
          'watch',
        );
        expect(
          batch.heartRate.firstWhere((b) => b.origin == null).deviceType,
          isNull,
        );
      },
    );

    test(
      'nilai tidak valid ditolak dengan alasan dan nilai tidak lazim tetap lewat',
      () {
        final t = DateTime.utc(2026, 11, 14, 3, 0);
        final batch = normalizer.normalize(
          HealthReadResult(
            measurements: [
              _hr(t, 0),
              _hr(t, 10),
              _hr(t, 400),
              _hr(t, double.nan),
              _hr(_now.add(const Duration(hours: 2)), 70),
              _hr(t, 235),
              RawMeasurement(
                id: 's1',
                metric: WearableMetric.sleep,
                value: 0,
                unit: 'minute',
                startTime: t,
                endTime: t.add(const Duration(seconds: 20)),
              ),
              RawMeasurement(
                id: 'w1',
                metric: WearableMetric.weight,
                value: 5,
                unit: 'kg',
                startTime: t,
                endTime: t,
              ),
              RawMeasurement(
                id: 'g1',
                metric: WearableMetric.glucose,
                value: -3,
                unit: 'mg/dL',
                startTime: t,
                endTime: t,
              ),
              RawMeasurement(
                id: 'st1',
                metric: WearableMetric.steps,
                value: -1,
                unit: 'count',
                startTime: DateTime(2026, 11, 13),
                endTime: DateTime(2026, 11, 14),
              ),
              RawMeasurement(
                id: 'st2',
                metric: WearableMetric.steps,
                value: 100,
                unit: 'count',
                startTime: DateTime(2026, 11, 20),
                endTime: DateTime(2026, 11, 21),
              ),
            ],
          ),
        );
        expect(batch.rejected, {
          'HEART_RATE_OUT_OF_DOMAIN': 2 + 1,
          'NOT_A_NUMBER': 1,
          'FUTURE_TIMESTAMP': 1 + 1,
          'SLEEP_DURATION_OUT_OF_RANGE': 1,
          'WEIGHT_OUT_OF_RANGE': 1,
          'GLUCOSE_OUT_OF_RANGE': 1,
          'STEPS_INVALID': 1,
        });
        expect(batch.heartRate.single.max, 235);
        expect(batch.steps, isEmpty);
      },
    );

    test(
      'langkah memakai tanggal lokal, tanpa angka nol palsu, dan duplikat tanggal diambil yang terakhir',
      () {
        final batch = normalizer.normalize(
          HealthReadResult(
            measurements: [
              RawMeasurement(
                id: 'a',
                metric: WearableMetric.steps,
                value: 1000,
                unit: 'count',
                startTime: DateTime(2026, 11, 13),
                endTime: DateTime(2026, 11, 14),
              ),
              RawMeasurement(
                id: 'b',
                metric: WearableMetric.steps,
                value: 1200,
                unit: 'count',
                startTime: DateTime(2026, 11, 13, 0, 0, 1),
                endTime: DateTime(2026, 11, 14),
              ),
            ],
          ),
        );
        expect(batch.steps.single.localDate, '2026-11-13');
        expect(batch.steps.single.steps, 1200);
        final zero = normalizer.normalize(
          HealthReadResult(
            measurements: [
              RawMeasurement(
                id: 'z',
                metric: WearableMetric.steps,
                value: 0,
                unit: 'count',
                startTime: DateTime(2026, 11, 12),
                endTime: DateTime(2026, 11, 13),
              ),
            ],
          ),
        );
        expect(zero.steps, isEmpty);
        expect(zero.rejected, isEmpty);
        expect(zero.isEmpty, isTrue);

        expect(normalizer.normalize(const HealthReadResult()).isEmpty, isTrue);
      },
    );

    test(
      'sesi tidur dari dua sumber yang tumpang tindih ditandai sebagai konflik',
      () {
        final s = DateTime.utc(2026, 11, 13, 16, 0);
        final batch = normalizer.normalize(
          HealthReadResult(
            measurements: [
              RawMeasurement(
                id: 'a',
                metric: WearableMetric.sleep,
                value: 450,
                unit: 'minute',
                startTime: s,
                endTime: s.add(const Duration(hours: 7)),
                origin: 'one',
              ),
              RawMeasurement(
                id: 'b',
                metric: WearableMetric.sleep,
                value: 400,
                unit: 'minute',
                startTime: s.add(const Duration(minutes: 30)),
                endTime: s.add(const Duration(hours: 7)),
                origin: 'two',
              ),
              RawMeasurement(
                id: 'c',
                metric: WearableMetric.sleep,
                value: 60,
                unit: 'minute',
                startTime: s.add(const Duration(hours: 9)),
                endTime: s.add(const Duration(hours: 10)),
                origin: 'two',
              ),
            ],
          ),
        );
        expect(batch.sleep, hasLength(3));
        expect(batch.sleepConflicts, 1);
      },
    );

    test(
      'sesi olahraga di luar 1..1440 menit ditolak dan id ganda digabung',
      () {
        DeviceSession w(String id, int m) => DeviceSession(
          externalId: id,
          activityType: 'walking',
          startedAt: DateTime.utc(2026, 11, 14, 1),
          durationMinutes: m,
        );
        final batch = normalizer.normalize(
          HealthReadResult(
            workouts: [w('a', 20), w('a', 25), w('b', 0), w('c', 2000)],
          ),
        );
        expect(batch.workouts.map((e) => e.externalId), ['a']);
        expect(batch.workouts.single.durationMinutes, 25);
        expect(batch.rejected['WORKOUT_DURATION_OUT_OF_RANGE'], 2);
      },
    );
  });

  group('sumber simulasi', () {
    test(
      'deterministik: jam yang sama menghasilkan data yang sama dan semuanya berlabel simulasi',
      () async {
        final a = await _granted();
        final b = await _granted();
        final req = HealthReadRequest(
          metrics: WearableMetric.values.toSet(),
          from: _now.subtract(const Duration(days: 2)),
          to: _now,
        );
        final ra = await a.read(req), rb = await b.read(req);
        expect(ra.measurements.length, rb.measurements.length);
        expect(
          ra.measurements.map((m) => m.value).toList(),
          rb.measurements.map((m) => m.value).toList(),
        );
        expect(ra.measurements.every((m) => m.isSimulated), isTrue);
        expect(a.sourceKey, 'simulated');
        expect(a.isSimulated, isTrue);
        expect(
          ra.measurements.map((m) => m.metric).toSet(),
          containsAll([
            WearableMetric.steps,
            WearableMetric.heartRate,
            WearableMetric.restingHeartRate,
            WearableMetric.sleep,
            WearableMetric.weight,
            WearableMetric.glucose,
          ]),
        );
        expect(ra.workouts, isNotEmpty);
      },
    );

    test('profil tanpa data dan izin dicabut tidak mengarang nilai', () async {
      final req = HealthReadRequest(
        metrics: WearableMetric.values.toSet(),
        from: _now.subtract(const Duration(days: 2)),
        to: _now,
      );
      final none = await _granted(profile: SimulationProfile.noDataDay);
      final r = await none.read(req);
      expect(r.measurements, isEmpty);
      expect(r.workouts, isEmpty);
      final revoked = await _granted(
        profile: SimulationProfile.permissionRevoked,
      );
      expect(await revoked.hasAccess(WearableMetric.steps), isFalse);
      expect(await revoked.requestAccess(WearableMetric.steps), isFalse);
    });

    test(
      'dua sumber dan sumber bertentangan menghasilkan sesi tidur tumpang tindih dari asal berbeda',
      () async {
        final req = HealthReadRequest(
          metrics: const {WearableMetric.sleep, WearableMetric.heartRate},
          from: _now.subtract(const Duration(days: 1)),
          to: _now,
        );
        for (final p in [
          SimulationProfile.multipleSources,
          SimulationProfile.conflictingSources,
        ]) {
          final s = await _granted(profile: p);
          final r = await s.read(req);
          final sleep = r.measurements
              .where((m) => m.metric == WearableMetric.sleep)
              .toList();
          expect(sleep.map((m) => m.origin).toSet().length, 2, reason: p.name);
          final batch = HealthNormalizer(clock: () => _now).normalize(r);
          expect(batch.sleepConflicts, greaterThan(0), reason: p.name);
        }
        final multi = await _granted(
          profile: SimulationProfile.multipleSources,
        );
        final hr = (await multi.read(
          req,
        )).measurements.where((m) => m.metric == WearableMetric.heartRate);
        expect(hr.map((m) => m.origin).toSet(), hasLength(2));
      },
    );

    test(
      'data lama bergeser ke masa lalu dan data sebagian hanya mencakup sebagian hari',
      () async {
        final req = HealthReadRequest(
          metrics: const {WearableMetric.heartRate, WearableMetric.sleep},
          from: _now.subtract(const Duration(days: 14)),
          to: _now,
        );
        final stale = await (await _granted(
          profile: SimulationProfile.staleMeasurements,
        )).read(req);
        final newest = stale.measurements
            .map((m) => m.startTime)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        expect(_now.difference(newest), greaterThan(const Duration(days: 3)));
        final partial = await (await _granted(
          profile: SimulationProfile.partialDay,
        )).read(req);
        expect(
          partial.measurements.where((m) => m.metric == WearableMetric.sleep),
          isEmpty,
        );
        final hours = partial.measurements.map((m) => m.startTime.hour).toSet();
        expect(hours.every((h) => h >= 6 && h <= 12), isTrue);
      },
    );
  });

  group('mesin status koneksi', () {
    DeviceConnectionState derive({
      HealthPlatformState platform = HealthPlatformState.available,
      Set<WearableMetric> enabled = const {WearableMetric.steps},
      Set<WearableMetric> granted = const {WearableMetric.steps},
      bool syncing = false,
      String? error,
      DateTime? lastSuccess,
      bool hasData = true,
    }) => deriveConnectionState(
      platform: platform,
      enabled: enabled,
      granted: granted,
      syncing: syncing,
      now: _now,
      lastErrorCode: error,
      lastSuccessAt: lastSuccess,
      hasData: hasData,
    );

    test('urutan prioritas dan seluruh keadaan', () {
      expect(
        derive(platform: HealthPlatformState.unsupportedPlatform),
        DeviceConnectionState.platformUnavailable,
      );
      expect(
        derive(platform: HealthPlatformState.healthConnectUnavailable),
        DeviceConnectionState.healthConnectUnavailable,
      );
      expect(
        derive(platform: HealthPlatformState.installRequired),
        DeviceConnectionState.healthConnectUnavailable,
      );
      expect(derive(enabled: {}), DeviceConnectionState.importDisabled);
      expect(derive(syncing: true), DeviceConnectionState.syncing);
      expect(derive(granted: {}), DeviceConnectionState.notAuthorized);
      expect(
        derive(error: 'NETWORK_UNAVAILABLE'),
        DeviceConnectionState.syncFailed,
      );
      expect(
        derive(hasData: false, lastSuccess: _now),
        DeviceConnectionState.authorizedNoData,
      );
      expect(
        derive(lastSuccess: _now.subtract(const Duration(days: 3))),
        DeviceConnectionState.syncStale,
      );
      expect(derive(lastSuccess: null), DeviceConnectionState.syncStale);
      expect(
        derive(lastSuccess: _now.subtract(const Duration(hours: 2))),
        DeviceConnectionState.dataAvailable,
      );
    });

    test(
      'Health Connect berisi data tidak pernah menaikkan status jam tangan dengan sendirinya',
      () {
        for (final s in DeviceConnectionState.values) {
          expect(
            s.title.toLowerCase().contains('jam tangan'),
            isFalse,
            reason: s.name,
          );
          expect(
            s.explanation.toLowerCase().contains('terhubung ke jam tangan'),
            isFalse,
          );
        }
      },
    );
  });

  group('penyimpanan sinkron', () {
    test('kursor per akun dan per metrik, dan reset', () async {
      final kv = MemoryKeyValueStore();
      final a = SyncStore(kv, 'a'), b = SyncStore(kv, 'b');
      await a.setCursor('health_connect', WearableMetric.heartRate, _now);
      expect(
        await a.cursor('health_connect', WearableMetric.heartRate),
        _now.toUtc(),
      );
      expect(await a.cursor('health_connect', WearableMetric.steps), isNull);
      expect(await a.cursor('simulated', WearableMetric.heartRate), isNull);
      expect(
        await b.cursor('health_connect', WearableMetric.heartRate),
        isNull,
      );
      await a.resetCursor('health_connect', WearableMetric.heartRate);
      expect(
        await a.cursor('health_connect', WearableMetric.heartRate),
        isNull,
      );
    });

    test(
      'outbox dibatasi, yang terlama dibuang dan jumlahnya dilaporkan',
      () async {
        final store = SyncStore(MemoryKeyValueStore(), 'a');
        var dropped = 0;
        for (var i = 0; i < SyncStore.maxOutboxEntries + 3; i++) {
          dropped += await store.enqueue(
            OutboxEntry(
              id: 'e$i',
              source: 'health_connect',
              metric: WearableMetric.steps,
              items: [
                {'i': i},
              ],
              createdAt: _now,
            ),
          );
        }
        expect(dropped, 3);
        final all = await store.outbox();
        expect(all, hasLength(SyncStore.maxOutboxEntries));
        expect(all.first.id, 'e3');
        await store.clear();
        expect(await store.outbox(), isEmpty);
      },
    );

    test('outbox tidak bocor antar akun dan entri rusak diabaikan', () async {
      final kv = MemoryKeyValueStore();
      final a = SyncStore(kv, 'a'), b = SyncStore(kv, 'b');
      await a.enqueue(
        OutboxEntry(
          id: 'x',
          source: 'health_connect',
          metric: WearableMetric.sleep,
          items: [
            {'k': 1},
          ],
          createdAt: _now,
        ),
      );
      expect(await b.outbox(), isEmpty);
      await kv.write(
        'beokay.devsync.outbox.c',
        '[{"id":"bad"},{"id":"ok","metric":"steps","createdAt":"2026-11-14T00:00:00Z","items":[]}]',
      );
      expect((await SyncStore(kv, 'c').outbox()).map((e) => e.id), ['ok']);
      await kv.write('beokay.devsync.outbox.d', 'bukan json');
      expect(await SyncStore(kv, 'd').outbox(), isEmpty);
    });
  });

  group('koordinator sinkron', () {
    test(
      'sinkron pertama membaca 14 hari, mengirim sumber simulasi tanpa berat/glukosa, dan memajukan kursor',
      () async {
        final env = _Env();
        final spy = _Spy(await _granted(metrics: WearableMetric.values));
        final report = await env
            .coordinator(spy)
            .sync(
              enabled: {
                WearableMetric.steps,
                WearableMetric.heartRate,
                WearableMetric.restingHeartRate,
                WearableMetric.sleep,
                WearableMetric.workouts,
                WearableMetric.weight,
                WearableMetric.glucose,
              },
              trigger: SyncTrigger.manual,
            );
        expect(report.hasFailure, isFalse);
        expect(report.simulated, isTrue);
        expect(spy.requests.single.stepsDays, 14);
        expect(_now.difference(spy.requests.single.from).inDays, 14);
        final bodies = env
            .posts('/api/me/device-import')
            .map((r) => jsonDecode(r.body) as Map<String, dynamic>)
            .toList();
        expect(bodies.every((b) => b['source'] == 'simulated'), isTrue);
        expect(
          bodies.any(
            (b) => b.containsKey('weights') || b.containsKey('glucose'),
          ),
          isFalse,
        );
        expect(
          bodies.where((b) => b.containsKey('heartRate')).length,
          greaterThan(1),
        );
        expect(
          bodies
              .where((b) => b.containsKey('heartRate'))
              .every(
                (b) =>
                    (b['heartRate'] as List).length <=
                    batchLimits[WearableMetric.heartRate]!,
              ),
          isTrue,
        );
        expect(env.posts('/api/me/activities/import'), hasLength(1));
        expect(
          report.outcomes[WearableMetric.weight]!.skippedReason,
          'SIMULATED_NOT_SENT',
        );
        expect(
          report.outcomes[WearableMetric.glucose]!.skippedReason,
          'SIMULATED_NOT_SENT',
        );
        expect(report.totals.imported, greaterThan(0));
        for (final m in [
          WearableMetric.steps,
          WearableMetric.heartRate,
          WearableMetric.sleep,
        ]) {
          expect(await env.store.cursor('simulated', m), _now.toUtc());
        }
        expect(
          env
              .checkpoints()
              .map((r) => (jsonDecode(r.body) as Map)['outcome'])
              .toSet(),
          {'success'},
        );
      },
    );

    test(
      'sinkron berikutnya inkremental: jendela dari kursor dikurangi 24 jam dan langkah 3 hari',
      () async {
        final env = _Env();
        final spy = _Spy(await _granted());
        final c = env.coordinator(spy);
        final enabled = {
          WearableMetric.steps,
          WearableMetric.heartRate,
          WearableMetric.sleep,
        };
        await c.sync(enabled: enabled, trigger: SyncTrigger.manual);
        await c.sync(enabled: enabled, trigger: SyncTrigger.resume);
        final second = spy.requests.last;
        expect(second.stepsDays, 3);
        expect(_now.difference(second.from), const Duration(hours: 24));
        expect(second.from.millisecondsSinceEpoch % bucketMillis, 0);
        await c.sync(enabled: enabled, trigger: SyncTrigger.manual);
        expect(spy.requests.last.stepsDays, 14);
      },
    );

    test('dua pemanggilan bersamaan digabung menjadi satu sinkron', () async {
      final env = _Env();
      final spy = _Spy(await _granted());
      final c = env.coordinator(spy);
      final a = c.sync(
        enabled: {WearableMetric.steps},
        trigger: SyncTrigger.resume,
      );
      final b = c.sync(
        enabled: {WearableMetric.steps},
        trigger: SyncTrigger.manual,
      );
      expect(identical(a, b), isTrue);
      expect(c.running, isTrue);
      await a;
      expect(c.running, isFalse);
      expect(spy.requests, hasLength(1));
      await c.sync(
        enabled: {WearableMetric.steps},
        trigger: SyncTrigger.manual,
      );
      expect(spy.requests, hasLength(2));
    });

    test(
      'jaringan putus: batch masuk outbox, kursor tidak maju, lalu terkuras saat jaringan pulih',
      () async {
        var online = false;
        final env = _Env(
          handler: (r) {
            if (!online && r.url.path != '/api/me/device-sync/checkpoints') {
              throw http.ClientException('offline');
            }
            return null;
          },
        );
        final spy = _Spy(await _granted());
        final c = env.coordinator(spy);
        final enabled = {
          WearableMetric.steps,
          WearableMetric.heartRate,
          WearableMetric.sleep,
        };
        final failed = await c.sync(
          enabled: enabled,
          trigger: SyncTrigger.manual,
        );
        expect(failed.hasFailure, isTrue);
        expect(
          failed.outcomes[WearableMetric.heartRate]!.errorCode,
          'NETWORK_UNAVAILABLE',
        );
        expect(
          await env.store.cursor('simulated', WearableMetric.heartRate),
          isNull,
        );
        final queued = await env.store.outbox();
        expect(queued, isNotEmpty);
        expect(
          queued.map((e) => e.metric).toSet(),
          containsAll([WearableMetric.heartRate, WearableMetric.steps]),
        );
        online = true;
        final recovered = await c.sync(
          enabled: enabled,
          trigger: SyncTrigger.networkRestored,
        );
        expect(recovered.hasFailure, isFalse);
        expect(recovered.drainedFromOutbox, queued.length);
        expect(await env.store.outbox(), isEmpty);
        expect(
          await env.store.cursor('simulated', WearableMetric.heartRate),
          _now.toUtc(),
        );
      },
    );

    test(
      'penarikan consent menghentikan sinkron dan menghapus antrean tertunda',
      () async {
        var deny = false;
        final env = _Env(
          handler: (r) {
            if (deny && r.url.path == '/api/me/device-import') {
              return _error(403, 'CONSENT_REQUIRED');
            }
            if (r.url.path == '/api/me/device-import' && !deny) {
              throw http.ClientException('offline');
            }
            return null;
          },
        );
        final spy = _Spy(await _granted());
        final c = env.coordinator(spy);
        await c.sync(
          enabled: {WearableMetric.heartRate},
          trigger: SyncTrigger.manual,
        );
        expect(await env.store.outbox(), isNotEmpty);
        deny = true;
        final r = await c.sync(
          enabled: {WearableMetric.heartRate},
          trigger: SyncTrigger.resume,
        );
        expect(r.blockedBy, 'CONSENT_REQUIRED');
        expect(await env.store.outbox(), isEmpty);
        expect(spy.requests, hasLength(1));
      },
    );

    test(
      'izin dicabut dilaporkan sebagai PERMISSION_REVOKED bila pernah berhasil, selain itu PERMISSION_DENIED',
      () async {
        final env = _Env();
        final source = await _granted();
        final c = env.coordinator(source);
        await c.sync(
          enabled: {WearableMetric.steps},
          trigger: SyncTrigger.manual,
        );
        source.revokeAll();
        final r = await c.sync(
          enabled: {WearableMetric.steps, WearableMetric.heartRate},
          trigger: SyncTrigger.manual,
        );
        expect(
          r.outcomes[WearableMetric.steps]!.errorCode,
          'PERMISSION_REVOKED',
        );
        expect(
          r.outcomes[WearableMetric.heartRate]!.errorCode,
          'PERMISSION_DENIED',
        );
        final reported = env
            .checkpoints()
            .map((x) => (jsonDecode(x.body) as Map)['errorCode'])
            .whereType<String>()
            .toSet();
        expect(reported, {'PERMISSION_REVOKED', 'PERMISSION_DENIED'});
      },
    );

    test(
      'Health Connect tidak tersedia atau perlu dipasang: tidak mengirim apa pun',
      () async {
        final env = _Env();
        final a = await env
            .coordinator(
              _Unavailable(HealthPlatformState.healthConnectUnavailable),
            )
            .sync(enabled: {WearableMetric.steps});
        expect(a.blockedBy, 'HEALTH_CONNECT_UNAVAILABLE');
        final b = await env
            .coordinator(_Unavailable(HealthPlatformState.installRequired))
            .sync(enabled: {WearableMetric.steps});
        expect(b.blockedBy, 'HEALTH_CONNECT_INSTALL_REQUIRED');
        final c = await env
            .coordinator(_Unavailable(HealthPlatformState.unsupportedPlatform))
            .sync(enabled: {WearableMetric.steps});
        expect(c.blockedBy, 'PLATFORM_UNSUPPORTED');
        expect(env.posts('/api/me/device-import'), isEmpty);
        expect(
          (await env.coordinator(await _granted()).sync(enabled: {})).blockedBy,
          'IMPORT_DISABLED',
        );
      },
    );

    test(
      'akun berganti di tengah sinkron: tidak ada pengiriman lagi dan kursor tidak maju',
      () async {
        late _Env env;
        env = _Env(
          handler: (r) {
            if (r.url.path == '/api/me/device-import') env.accountOk = false;
            return null;
          },
        );
        final spy = _Spy(await _granted());
        final r = await env
            .coordinator(spy)
            .sync(
              enabled: {WearableMetric.heartRate, WearableMetric.steps},
              trigger: SyncTrigger.manual,
            );
        expect(env.posts('/api/me/device-import'), hasLength(1));
        expect(r.hasFailure, isTrue);
        expect(
          await env.store.cursor('simulated', WearableMetric.heartRate),
          isNull,
        );
        final other = await env
            .coordinator(spy, current: () => false)
            .sync(enabled: {WearableMetric.steps});
        expect(other.blockedBy, 'ACCOUNT_CHANGED');
      },
    );

    test(
      'kegagalan server tidak memajukan kursor dan dilaporkan ke checkpoint',
      () async {
        final env = _Env(
          handler: (r) => r.url.path == '/api/me/device-import'
              ? _error(500, 'INTERNAL_ERROR')
              : null,
        );
        final r = await env
            .coordinator(await _granted())
            .sync(enabled: {WearableMetric.steps}, trigger: SyncTrigger.manual);
        expect(r.outcomes[WearableMetric.steps]!.errorCode, 'SERVER_ERROR');
        expect(
          await env.store.cursor('simulated', WearableMetric.steps),
          isNull,
        );
        expect(
          env.checkpoints().map(
            (x) => (jsonDecode(x.body) as Map)['errorCode'],
          ),
          contains('SERVER_ERROR'),
        );
      },
    );

    test(
      'server produksi menolak data simulasi: dilaporkan jelas dan tidak dianggap sukses',
      () async {
        final env = _Env(
          handler: (r) => r.url.path == '/api/me/device-import'
              ? _error(403, 'SIMULATION_DISABLED')
              : null,
        );
        final r = await env
            .coordinator(await _granted())
            .sync(
              enabled: {WearableMetric.heartRate},
              trigger: SyncTrigger.manual,
            );
        expect(
          r.outcomes[WearableMetric.heartRate]!.errorCode,
          'SIMULATION_DISABLED',
        );
        expect(
          await env.store.cursor('simulated', WearableMetric.heartRate),
          isNull,
        );
      },
    );
  });
}
