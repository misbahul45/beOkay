import 'dart:convert';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/offline/offline_queue.dart';
import 'package:app/core/offline/sync_controller.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/core/theme/app_colors.dart';
import 'package:app/core/widgets/pill_button.dart';
import 'package:app/core/widgets/settings_group.dart';
import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/auth/data/session_user.dart';
import 'package:app/features/devices/application/devices_controller.dart';
import 'package:app/features/devices/data/health_source.dart';
import 'package:app/features/devices/data/simulated_source.dart';
import 'package:app/features/devices/presentation/devices_screen.dart';
import 'package:app/features/devices/presentation/heart_rate_screen.dart';
import 'package:app/features/devices/presentation/wearable_today_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

class _Auth extends AuthController {
  @override
  AuthState build() => const AuthAuthenticated(
    SessionUser(id: 'u1', email: 'u@x.test', name: 'U', emailVerified: true),
  );
}

class _SimOn extends SimulationProfileController {
  @override
  SimulationProfile? build() => SimulationProfile.activeDay;
}

class _Unavailable implements HealthDataSource {
  @override
  String get sourceKey => 'health_connect';
  @override
  bool get isSimulated => false;
  @override
  Future<SourceCapabilities> capabilities() async => const SourceCapabilities(
    platform: HealthPlatformState.healthConnectUnavailable,
  );
  @override
  Future<bool> hasAccess(WearableMetric metric) async => false;
  @override
  Future<bool> requestAccess(WearableMetric metric) async => false;
  @override
  Future<HealthReadResult> read(HealthReadRequest request) async =>
      const HealthReadResult();
}

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

class _Api {
  _Api() {
    final tokens = MemoryTokenStorage()..write('t');
    client = ApiClient(
      tokens: tokens,
      baseUrl: 'http://test',
      client: MockClient((r) async {
        seen.add(r);
        return _route(r) ?? _json({}, 404);
      }),
    );
  }
  final seen = <http.Request>[];
  late final ApiClient client;
  var prefs = <String, bool>{
    'workouts': false,
    'steps': false,
    'weight': false,
    'glucose': false,
    'sleep': false,
    'heartRate': false,
    'restingHeartRate': false,
  };
  Map<String, dynamic> status = {
    'signals': [],
    'origins': [],
    'sourceApplications': [],
    'detectedDeviceTypes': [],
    'usedForCoaching': false,
    'watchVerification': 'WATCH_NOT_VERIFIED',
    'syncState': 'NEVER_SYNCED',
    'lastSyncAt': {},
    'notice': 'Hari tanpa data perangkat tidak pernah dianggap tidak aktif.',
  };
  http.Response? Function(http.Request r)? override;
  Map<String, dynamic>? heartRate;
  Map<String, dynamic>? heartRateDay;
  Map<String, dynamic>? today;
  int importFailures = 0;

  http.Response? _route(http.Request r) {
    final custom = override?.call(r);
    if (custom != null) return custom;
    final path = r.url.path;
    if (path == '/api/me/device-import/preferences') {
      if (r.method == 'PATCH') {
        prefs = {...prefs, ...(jsonDecode(r.body) as Map).cast<String, bool>()};
      }
      return _json(prefs);
    }
    if (path == '/api/me/devices/status') return _json(status);
    if (path == '/api/me/device-sync/checkpoints') return _json({});
    if (path == '/api/me/device-import') {
      if (importFailures > 0) {
        importFailures--;
        return _json({
          'error': {'code': 'INTERNAL_ERROR', 'message': 'x'},
        }, 500);
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
    if (path == '/api/me/activities/import') {
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
    if (path == '/api/me/heart-rate' && heartRate != null) {
      return _json(heartRate!);
    }
    if (path == '/api/me/heart-rate/day' && heartRateDay != null) {
      return _json(heartRateDay!);
    }
    if (path == '/api/me/devices/today' && today != null) return _json(today!);
    return null;
  }

  Map<String, dynamic> body(String path, [String method = 'POST']) =>
      jsonDecode(
            seen
                .lastWhere((r) => r.url.path == path && r.method == method)
                .body,
          )
          as Map<String, dynamic>;
  int count(String path, String method) =>
      seen.where((r) => r.url.path == path && r.method == method).length;
}

Future<void> _pump(
  WidgetTester tester,
  _Api api,
  Widget home, {
  List<Override> overrides = const [],
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: home),
      ),
      GoRoute(
        path: Routes.heartRate,
        builder: (_, _) => const HeartRateScreen(),
      ),
      GoRoute(path: Routes.devices, builder: (_, _) => const DevicesScreen()),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        authControllerProvider.overrideWith(_Auth.new),
        apiClientProvider.overrideWithValue(api.client),
        keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
        ...overrides,
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _switchOf(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(SettingsRow)),
  matching: find.byType(Switch),
);

PillButton _button(WidgetTester tester, String label) =>
    tester.widget<PillButton>(find.widgetWithText(PillButton, label));

Map<String, dynamic> _hrSummary({
  bool empty = false,
  bool stale = false,
  bool simulated = false,
}) {
  final series = [
    for (var i = 0; i < 7; i++)
      {
        'date': '2026-11-${(8 + i).toString().padLeft(2, '0')}',
        'observedBuckets': empty || i < 4 ? 0 : 40,
        'sampleCount': empty || i < 4 ? 0 : 160,
        'coverage': empty || i < 4 ? 0 : 0.14,
        'minimum': empty || i < 4 ? null : 55 + i,
        'maximum': empty || i < 4 ? null : 110 + i,
        'average': empty || i < 4 ? null : 72.5,
        'restingHeartRate': empty || i < 4 ? null : 60,
        'lastMeasurementAt': empty || i < 4
            ? null
            : '2026-11-${8 + i}T05:00:00.000Z',
        'needsReview': false,
        'insufficient': empty || i < 4,
      },
  ];
  return {
    'days': 7,
    'bucketMinutes': 5,
    'methodology':
        'Rata-rata sampel yang teramati (bukan rata-rata berbobot waktu).',
    'enabled': {'heartRate': true, 'restingHeartRate': true},
    'series': series,
    'latest': empty
        ? null
        : {
            'bpm': 74,
            'windowStart': DateTime.now()
                .subtract(const Duration(minutes: 20))
                .toUtc()
                .toIso8601String(),
            'windowMinutes': 5,
            'sampleCount': 5,
            'dataOrigin': 'com.samsung.android.wear.shealth',
            'deviceType': 'watch',
            'simulated': simulated,
          },
    'restingLatest': empty
        ? null
        : {
            'bpm': 61,
            'measuredAt': '2026-11-14T00:00:00.000Z',
            'simulated': false,
          },
    'freshness': empty ? 'NO_DATA' : (stale ? 'STALE' : 'FRESH'),
    'simulated': simulated,
    'notice':
        'Angka detak jantung dari perangkat bersifat deskriptif dan bukan diagnosis.',
  };
}

Map<String, dynamic> _hrDay({bool gaps = true}) => {
  'timezone': 'Asia/Jakarta',
  'date': '2026-11-14',
  'summary': {
    'date': '2026-11-14',
    'observedBuckets': 3,
    'sampleCount': 15,
    'coverage': 0.01,
    'minimum': 58,
    'maximum': 99,
    'average': 71.4,
    'restingHeartRate': 60,
    'lastMeasurementAt': '2026-11-14T05:10:00.000Z',
    'needsReview': true,
    'insufficient': false,
  },
  'buckets': [
    {
      'start': '2026-11-14T01:00:00.000Z',
      'min': 58,
      'max': 70,
      'avg': 64.0,
      'sampleCount': 5,
      'dataOrigin': 'a.b',
      'needsReview': false,
      'simulated': false,
    },
    {
      'start': '2026-11-14T01:05:00.000Z',
      'min': 60,
      'max': 75,
      'avg': 66.0,
      'sampleCount': 5,
      'dataOrigin': 'a.b',
      'needsReview': false,
      'simulated': false,
    },
    {
      'start': gaps ? '2026-11-14T05:10:00.000Z' : '2026-11-14T01:10:00.000Z',
      'min': 70,
      'max': 99,
      'avg': 85.0,
      'sampleCount': 5,
      'dataOrigin': 'a.b',
      'needsReview': true,
      'simulated': false,
    },
  ],
  'resting': [
    {'bpm': 60, 'measuredAt': '2026-11-14T00:00:00.000Z', 'simulated': false},
  ],
  'notice': 'x',
};

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));
  tearDown(() => AppColors.use(Brightness.light));

  testWidgets(
    'keadaan awal: semua jenis data mati, tombol sinkron nonaktif, jam tangan belum terverifikasi',
    (tester) async {
      final api = _Api();
      final source = SimulatedHealthDataSource();
      await _pump(
        tester,
        api,
        const DevicesScreen(),
        overrides: [healthDataSourceProvider.overrideWithValue(source)],
      );
      expect(find.text('Perangkat & Kesehatan'), findsOneWidget);
      expect(find.text('Belum ada data yang diimpor'), findsOneWidget);
      for (final label in [
        'Langkah',
        'Detak jantung',
        'Detak jantung istirahat',
        'Aktivitas olahraga',
        'Tidur',
        'Berat badan',
        'Glukosa',
      ]) {
        expect(
          tester.widget<Switch>(_switchOf(label)).value,
          isFalse,
          reason: label,
        );
      }
      expect(_button(tester, 'Sinkronkan sekarang').onPressed, isNull);
      expect(
        find.textContaining('Jam tangan: belum terverifikasi'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Belum didukung: Energi aktif, Saturasi oksigen, Variabilitas detak jantung',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Belum ada sumber data'), findsOneWidget);
      expect(
        find.textContaining(
          RegExp('jam tangan (terhubung|tersambung)', caseSensitive: false),
        ),
        findsNothing,
      );
      expect(api.count('/api/me/device-import', 'POST'), 0);
    },
  );

  testWidgets(
    'menyalakan detak jantung meminta izin, menyimpan preferensi, lalu langsung menyinkronkan',
    (tester) async {
      final api = _Api();
      final source = SimulatedHealthDataSource();
      await _pump(
        tester,
        api,
        const DevicesScreen(),
        overrides: [healthDataSourceProvider.overrideWithValue(source)],
      );
      await tester.tap(_switchOf('Detak jantung'));
      await tester.pumpAndSettle();
      expect(source.granted, {WearableMetric.heartRate});
      expect(api.body('/api/me/device-import/preferences', 'PATCH'), {
        'heartRate': true,
      });
      final sent = api.body('/api/me/device-import');
      expect(sent['source'], 'simulated');
      expect((sent['heartRate'] as List), isNotEmpty);
      expect(
        (sent['heartRate'] as List).first.keys,
        containsAll([
          'bucketStart',
          'bpmMin',
          'bpmMax',
          'bpmAvg',
          'sampleCount',
        ]),
      );
      expect(sent.containsKey('weights'), isFalse);
      expect(find.textContaining('Diperbarui: detak jantung'), findsOneWidget);
      expect(tester.widget<Switch>(_switchOf('Detak jantung')).value, isTrue);
      expect(_button(tester, 'Sinkronkan sekarang').onPressed, isNotNull);
    },
  );

  testWidgets(
    'izin ditolak: tidak ada preferensi disimpan dan pesannya jelas',
    (tester) async {
      final api = _Api();
      final source = SimulatedHealthDataSource(
        profile: SimulationProfile.permissionRevoked,
      );
      await _pump(
        tester,
        api,
        const DevicesScreen(),
        overrides: [healthDataSourceProvider.overrideWithValue(source)],
      );
      await tester.tap(_switchOf('Langkah'));
      await tester.pumpAndSettle();
      expect(
        find.text('Izin langkah belum diberikan di Health Connect.'),
        findsOneWidget,
      );
      expect(api.count('/api/me/device-import/preferences', 'PATCH'), 0);
      expect(tester.widget<Switch>(_switchOf('Langkah')).value, isFalse);
    },
  );

  testWidgets(
    'Health Connect tidak tersedia: keadaan dan pesan tidak membuat aplikasi gagal',
    (tester) async {
      final api = _Api();
      await _pump(
        tester,
        api,
        const DevicesScreen(),
        overrides: [healthDataSourceProvider.overrideWithValue(_Unavailable())],
      );
      expect(find.text('Health Connect belum tersedia'), findsWidgets);
      await tester.tap(_switchOf('Langkah'));
      await tester.pumpAndSettle();
      expect(
        find.text('Health Connect belum tersedia di perangkat ini.'),
        findsOneWidget,
      );
      expect(api.count('/api/me/device-import/preferences', 'PATCH'), 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sinkronisasi gagal menampilkan kesalahan dengan Coba lagi, dan berhasil setelah diulang',
    (tester) async {
      final api = _Api()
        ..prefs['steps'] = true
        ..importFailures = 1;
      final source = SimulatedHealthDataSource();
      await source.requestAccess(WearableMetric.steps);
      await _pump(
        tester,
        api,
        const DevicesScreen(),
        overrides: [healthDataSourceProvider.overrideWithValue(source)],
      );
      await tester.tap(find.text('Sinkronkan sekarang'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Terjadi kendala di server'), findsOneWidget);
      expect(find.text('Sinkronisasi gagal'), findsOneWidget);
      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Diperbarui: langkah'), findsOneWidget);
      expect(find.text('Sinkronisasi gagal'), findsNothing);
    },
  );

  testWidgets(
    'izin dicabut setelah menyalakan: keadaan Izin belum diberikan dan laporan PERMISSION_REVOKED/DENIED',
    (tester) async {
      final api = _Api()..prefs['steps'] = true;
      final source = SimulatedHealthDataSource();
      await _pump(
        tester,
        api,
        const DevicesScreen(),
        overrides: [healthDataSourceProvider.overrideWithValue(source)],
      );
      expect(find.text('Izin belum diberikan'), findsWidgets);
      expect(find.textContaining('Izin belum diberikan'), findsWidgets);
      await tester.tap(find.text('Sinkronkan sekarang'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Izin Health Connect belum diberikan'),
        findsOneWidget,
      );
      expect(api.count('/api/me/device-import', 'POST'), 0);
      final failure = api.body('/api/me/device-sync/checkpoints', 'PUT');
      expect(failure['errorCode'], 'PERMISSION_DENIED');
    },
  );

  testWidgets(
    'Hentikan sinkronisasi mematikan semua jenis data setelah konfirmasi',
    (tester) async {
      final api = _Api()..prefs.updateAll((k, v) => true);
      final source = SimulatedHealthDataSource();
      await _pump(
        tester,
        api,
        const DevicesScreen(),
        overrides: [healthDataSourceProvider.overrideWithValue(source)],
      );
      await tester.scrollUntilVisible(
        find.text('Hentikan sinkronisasi'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Hentikan sinkronisasi'));
      await tester.pumpAndSettle();
      expect(find.text('Hentikan sinkronisasi?'), findsOneWidget);
      await tester.tap(find.text('Hentikan'));
      await tester.pumpAndSettle();
      final sent = api.body('/api/me/device-import/preferences', 'PATCH');
      expect(sent.values.every((v) => v == false), isTrue);
      expect(
        sent.keys,
        containsAll([
          'heartRate',
          'restingHeartRate',
          'steps',
          'sleep',
          'workouts',
          'weight',
          'glucose',
        ]),
      );
      expect(
        find.textContaining('Data yang sudah masuk tetap tersimpan'),
        findsWidgets,
      );
    },
  );

  testWidgets('banner simulasi tampil dengan label DATA SIMULASI', (
    tester,
  ) async {
    final api = _Api();
    await _pump(
      tester,
      api,
      const DevicesScreen(),
      overrides: [simulationProfileProvider.overrideWith(_SimOn.new)],
    );
    expect(find.textContaining('DATA SIMULASI · Hari aktif'), findsOneWidget);
    expect(find.text('MODE SIMULASI (PENGEMBANGAN)'), findsOneWidget);
  });

  testWidgets(
    'layar detak jantung: pengukuran terakhir, rentang, istirahat, tren, jeda tanpa data dan label aksesibel',
    (tester) async {
      final handle = tester.ensureSemantics();
      final api = _Api()
        ..heartRate = _hrSummary()
        ..heartRateDay = _hrDay();
      await _pump(tester, api, const HeartRateScreen());
      expect(find.text('74'), findsOneWidget);
      expect(find.text('bpm'), findsOneWidget);
      expect(find.textContaining('Rata-rata jendela 5 menit'), findsOneWidget);
      expect(
        find.textContaining('Samsung Health (jam tangan)'),
        findsOneWidget,
      );
      expect(find.text('61 bpm · '), findsNothing);
      expect(find.textContaining('61 bpm'), findsWidgets);
      expect(find.byType(HeartRateRangeChart), findsOneWidget);
      expect(find.byType(HeartRateDayChart), findsOneWidget);
      expect(find.textContaining('Tanpa data:'), findsOneWidget);
      expect(
        find.text('Ada nilai tidak lazim, perlu diperiksa'),
        findsOneWidget,
      );
      expect(
        find.textContaining('bukan rata-rata berbobot waktu'),
        findsOneWidget,
      );
      expect(find.textContaining('bukan diagnosis'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp('Pengukuran terakhir 74 denyut per menit'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Grafik rentang detak jantung harian')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('tanpa data')), findsWidgets);
      expect(find.textContaining('DATA SIMULASI'), findsNothing);
      handle.dispose();
    },
  );

  testWidgets(
    'layar detak jantung: data lama dan data simulasi diberi lencana',
    (tester) async {
      final api = _Api()
        ..heartRate = _hrSummary(stale: true, simulated: true)
        ..heartRateDay = _hrDay(gaps: false);
      await _pump(tester, api, const HeartRateScreen());
      expect(find.text('Data sudah lama'), findsOneWidget);
      expect(find.text('DATA SIMULASI'), findsOneWidget);
      expect(find.textContaining('Tanpa data:'), findsNothing);
    },
  );

  testWidgets(
    'layar detak jantung tanpa data: bukan 0 bpm, tidak ada grafik, tidak ada angka karangan',
    (tester) async {
      final api = _Api()
        ..heartRate = _hrSummary(empty: true)
        ..heartRateDay = {
          'timezone': 'Asia/Jakarta',
          'date': '2026-11-14',
          'summary': {
            'date': '2026-11-14',
            'observedBuckets': 0,
            'sampleCount': 0,
            'coverage': 0,
            'minimum': null,
            'maximum': null,
            'average': null,
            'restingHeartRate': null,
            'lastMeasurementAt': null,
            'needsReview': false,
            'insufficient': true,
          },
          'buckets': [],
          'resting': [],
          'notice': 'x',
        };
      await _pump(tester, api, const HeartRateScreen());
      expect(
        find.textContaining('Belum ada pengukuran. Ini bukan 0 bpm'),
        findsOneWidget,
      );
      expect(find.text('Belum ada data pada 7 hari terakhir.'), findsOneWidget);
      expect(find.text('Tidak ada data pada hari ini.'), findsOneWidget);
      expect(find.byType(HeartRateRangeChart), findsNothing);
      expect(find.byType(HeartRateDayChart), findsNothing);
      expect(find.text('0'), findsNothing);
      expect(
        find.text('Belum ada data istirahat dari perangkat.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'kartu Today: nilai ada, data lama, izin diperlukan, dan tanpa data tidak diisi nol',
    (tester) async {
      final api = _Api()
        ..today = {
          'steps': {
            'availability': 'HAS_DATA',
            'value': {'date': '2026-11-14', 'steps': 5400, 'simulated': false},
          },
          'heartRate': {
            'availability': 'STALE_DATA',
            'value': {
              'bpm': 80,
              'windowStart': '2026-11-10T00:00:00.000Z',
              'restingBpm': 59,
              'simulated': false,
            },
          },
          'sleep': {'availability': 'PERMISSION_REQUIRED', 'value': null},
          'activity': {'availability': 'NO_DATA', 'value': null},
        };
      await _pump(
        tester,
        api,
        const SingleChildScrollView(child: WearableTodayCard()),
      );
      expect(find.text('DARI PERANGKAT'), findsOneWidget);
      expect(find.text('5400 langkah'), findsOneWidget);
      expect(find.text('80 bpm'), findsOneWidget);
      expect(find.text('Istirahat 59 bpm'), findsOneWidget);
      expect(find.text('Sudah lama'), findsOneWidget);
      expect(find.text('Perlu izin Health Connect'), findsOneWidget);
      expect(find.text('Belum ada data'), findsOneWidget);
      expect(find.textContaining('0 menit'), findsNothing);
    },
  );

  testWidgets(
    'kartu Today tersembunyi bila tidak ada jenis data yang dinyalakan',
    (tester) async {
      final api = _Api()
        ..today = {
          for (final k in ['steps', 'heartRate', 'sleep', 'activity'])
            k: {'availability': 'NOT_ENABLED', 'value': null},
        };
      await _pump(
        tester,
        api,
        const SingleChildScrollView(child: WearableTodayCard()),
      );
      expect(find.text('DARI PERANGKAT'), findsNothing);
      final failing = _Api();
      await _pump(
        tester,
        failing,
        const SingleChildScrollView(child: WearableTodayCard()),
      );
      expect(find.text('DARI PERANGKAT'), findsNothing);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'teks besar 200% tanpa overflow pada layar perangkat dan detak jantung (${dark ? 'gelap' : 'terang'})',
      (tester) async {
        if (dark) AppColors.use(Brightness.dark);
        final api = _Api()
          ..prefs.updateAll((k, v) => true)
          ..heartRate = _hrSummary(stale: true, simulated: true)
          ..heartRateDay = _hrDay();
        final source = SimulatedHealthDataSource();
        await _pump(
          tester,
          api,
          const DevicesScreen(),
          overrides: [healthDataSourceProvider.overrideWithValue(source)],
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        await _pump(
          tester,
          api,
          const HeartRateScreen(),
          overrides: [healthDataSourceProvider.overrideWithValue(source)],
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        await _pump(
          tester,
          _Api()
            ..today = {
              'steps': {
                'availability': 'HAS_DATA',
                'value': {
                  'date': '2026-11-14',
                  'steps': 5400,
                  'simulated': true,
                },
              },
              'heartRate': {
                'availability': 'HAS_DATA',
                'value': {
                  'bpm': 80,
                  'windowStart': '2026-11-14T00:00:00.000Z',
                  'restingBpm': 59,
                  'simulated': true,
                },
              },
              'sleep': {
                'availability': 'HAS_DATA',
                'value': {'durationMinutes': 450, 'simulated': true},
              },
              'activity': {
                'availability': 'HAS_DATA',
                'value': {'minutes': 30, 'sessions': 1, 'simulated': true},
              },
            },
          const SingleChildScrollView(child: WearableTodayCard()),
          overrides: [healthDataSourceProvider.overrideWithValue(source)],
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('DATA SIMULASI'), findsOneWidget);
      },
    );
  }
}
