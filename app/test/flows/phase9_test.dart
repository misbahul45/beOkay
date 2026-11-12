import 'dart:convert';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/notifications/reminder_scheduler.dart';
import 'package:app/core/offline/offline_queue.dart';
import 'package:app/core/offline/sync_controller.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/core/theme/app_colors.dart';
import 'package:app/features/app_lock/app_lock.dart';
import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/auth/data/session_user.dart';
import 'package:app/features/devices/application/devices_controller.dart';
import 'package:app/features/devices/data/health_signals.dart';
import 'package:app/features/devices/presentation/devices_screen.dart';
import 'package:app/core/widgets/pill_button.dart';
import 'package:app/features/medication/application/medication_actions.dart';
import 'package:app/features/share/data/share_repository.dart';
import 'package:app/features/share/data/summary_pdf.dart';
import 'package:app/features/share/presentation/summary_report_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:qr_flutter/qr_flutter.dart';

class _Auth extends AuthController {
  @override
  AuthState build() => const AuthAuthenticated(
    SessionUser(id: 'u1', email: 'u@x.test', name: 'U', emailVerified: true),
  );
}

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

class _Api {
  final seen = <http.Request>[];
  http.Response? Function(http.Request r)? extra;
  late final ApiClient client;
  _Api() {
    final tokens = MemoryTokenStorage()..write('t');
    client = ApiClient(
      tokens: tokens,
      baseUrl: 'http://test',
      client: MockClient((r) async {
        seen.add(r);
        return extra?.call(r) ?? _json({}, 404);
      }),
    );
  }
  Map<String, dynamic> body(String path) =>
      jsonDecode(
            seen.lastWhere((r) => r.url.path == path && r.method != 'GET').body,
          )
          as Map<String, dynamic>;
  int count(String path, String method) =>
      seen.where((r) => r.url.path == path && r.method == method).length;
}

class _FakeSignals implements HealthSignalsSource {
  final granted = <SignalType>{};
  final requested = <SignalType>[];
  bool grant = true;
  @override
  Future<bool> available() async => true;
  @override
  Future<bool> hasAccess(SignalType type) async => granted.contains(type);
  @override
  Future<bool> requestAccess(SignalType type) async {
    requested.add(type);
    if (grant) granted.add(type);
    return grant;
  }

  @override
  Future<List<StepsDay>> readSteps(int days) async => const [
    StepsDay('2026-11-11', 7200),
    StepsDay('2026-11-12', 3100),
  ];
  @override
  Future<List<DevicePoint>> read(
    SignalType type,
    DateTime from,
    DateTime to,
  ) async => type == SignalType.weight
      ? [
          DevicePoint(
            'w1',
            DateTime.utc(2026, 11, 11, 1),
            DateTime.utc(2026, 11, 11, 1),
            72.4,
          ),
        ]
      : const [];
}

class _FakeAuthenticator implements DeviceAuthenticator {
  bool result = true;
  int calls = 0;
  @override
  Future<bool> available() async => true;
  @override
  Future<bool> authenticate(String reason) async {
    calls++;
    return result;
  }
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _Api api,
  Widget home, {
  List<Override> overrides = const [],
  MemoryKeyValueStore? store,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: home),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        authControllerProvider.overrideWith(_Auth.new),
        apiClientProvider.overrideWithValue(api.client),
        keyValueStoreProvider.overrideWithValue(store ?? MemoryKeyValueStore()),
        ...overrides,
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

Map<String, dynamic> _summary() => {
  'version': 'report-summary-v1',
  'person': {'name': 'Budi'},
  'days': 30,
  'period': {'start': '2026-10-14', 'end': '2026-11-12', 'days': 30},
  'generatedLocal': {'localDate': '2026-11-12', 'localTime': '07:00'},
  'statistics': [
    {
      'label': 'Median glukosa puasa',
      'value': 128,
      'unit': 'mg/dL',
      'state': 'READY',
      'sampleCount': 9,
      'sampleUnit': 'pengukuran',
      'coverage': {'daysWithData': 9, 'totalDays': 30},
    },
    {
      'label': 'Hari aktif',
      'value': null,
      'unit': null,
      'state': 'INSUFFICIENT_DATA',
      'sampleCount': 0,
      'sampleUnit': 'hari',
      'coverage': {'daysWithData': 0, 'totalDays': 30},
    },
  ],
  'steps': {'daysWithData': 5, 'medianSteps': 6400},
  'vitals': [
    {'label': 'Berat badan', 'value': '72 kg', 'date': '2026-11-10'},
  ],
  'labs': [
    {'label': 'HbA1c', 'value': '7,4 %', 'date': '2026-08-01'},
  ],
  'medications': [
    {'name': 'Metformin', 'strength': '500 mg', 'instructions': '2x sehari'},
  ],
  'disclaimer': 'Ringkasan deskriptif. Bukan hasil pemeriksaan.',
};

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets(
    'K-1: each device data type is switched on separately, asks for its own permission, and sync sends only enabled types',
    (tester) async {
      _tall(tester);
      final api = _Api();
      var prefs = {
        'workouts': false,
        'steps': false,
        'weight': false,
        'glucose': false,
        'sleep': false,
      };
      api.extra = (r) {
        if (r.url.path == '/api/me/device-import/preferences') {
          if (r.method == 'PATCH') {
            prefs = {
              ...prefs,
              ...(jsonDecode(r.body) as Map).cast<String, bool>(),
            };
          }
          return _json(prefs);
        }
        if (r.url.path == '/api/me/device-import') {
          return _json({
            'steps': {'upserted': 2},
            'weights': {'created': 0},
            'glucose': {'created': 0},
            'sleep': {'created': 0},
          });
        }
        return null;
      };
      final source = _FakeSignals();
      await _pump(
        tester,
        api,
        const DevicesScreen(),
        overrides: [healthSignalsSourceProvider.overrideWithValue(source)],
      );
      expect(find.text('Langkah harian'), findsOneWidget);
      expect(
        tester
            .widget<PillButton>(
              find.widgetWithText(PillButton, 'Sinkronkan 14 hari terakhir'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(source.requested, [SignalType.steps]);
      expect(api.body('/api/me/device-import/preferences'), {'steps': true});
      await tester.tap(find.text('Sinkronkan 14 hari terakhir'));
      await tester.pumpAndSettle();
      final sent = api.body('/api/me/device-import');
      expect(sent['steps'], hasLength(2));
      expect(sent['weights'], isEmpty);
      expect(find.textContaining('2 hari langkah'), findsOneWidget);
      source.grant = false;
      await tester.tap(find.byType(Switch).at(1));
      await tester.pumpAndSettle();
      expect(
        find.text('Izin berat badan belum diberikan di Health Connect.'),
        findsOneWidget,
      );
      expect(api.count('/api/me/device-import/preferences', 'PATCH'), 1);
    },
  );

  testWidgets(
    'S-6: with the app lock on, a cold start is locked until the device verifies; sensitive actions ask again',
    (tester) async {
      _tall(tester);
      final api = _Api();
      final auth = _FakeAuthenticator();
      final store = MemoryKeyValueStore();
      var c = await _pump(
        tester,
        api,
        const AppLockGate(child: Text('Isi aplikasi')),
        overrides: [deviceAuthenticatorProvider.overrideWithValue(auth)],
        store: store,
      );
      expect(find.text('Isi aplikasi'), findsOneWidget);
      expect(
        await c.read(appLockProvider.notifier).confirmSensitive('x'),
        isTrue,
      );
      expect(auth.calls, 0);
      expect(await c.read(appLockProvider.notifier).setEnabled(true), isTrue);
      expect(store.data['beokay.applock.u1'], 'on');
      await tester.pumpWidget(const SizedBox());
      c = await _pump(
        tester,
        api,
        const AppLockGate(child: Text('Isi aplikasi')),
        overrides: [deviceAuthenticatorProvider.overrideWithValue(auth)],
        store: store,
      );
      expect(find.text('beOkay terkunci'), findsOneWidget);
      auth.result = false;
      await tester.tap(find.widgetWithText(PillButton, 'Buka kunci'));
      await tester.pumpAndSettle();
      expect(find.text('beOkay terkunci'), findsOneWidget);
      auth.result = true;
      await tester.tap(find.widgetWithText(PillButton, 'Buka kunci'));
      await tester.pumpAndSettle();
      expect(find.text('Isi aplikasi'), findsOneWidget);
      auth.result = false;
      expect(
        await c.read(appLockProvider.notifier).confirmSensitive('Hapus akun'),
        isFalse,
      );
    },
  );

  testWidgets(
    'S-7/K-9: the summary shows ready statistics, the PDF is generated on the device, and a link needs confirmation, shows a QR code, and can be revoked',
    (tester) async {
      _tall(tester);
      final api = _Api();
      final links = <Map<String, dynamic>>[];
      api.extra = (r) {
        if (r.url.path == '/api/me/report-summary') return _json(_summary());
        if (r.url.path == '/api/me/share-links' && r.method == 'GET') {
          return _json({'items': links});
        }
        if (r.url.path == '/api/me/share-links') {
          final l = {
            'id': 'l1',
            'periodDays': 30,
            'label': null,
            'expiresAt': '2026-11-15T00:00:00Z',
            'active': true,
            'accessCount': 0,
            'url': 'https://api.beokay.test/s/${'a' * 43}',
          };
          links.add(l);
          return _json(l, 201);
        }
        if (r.url.path == '/api/me/share-links/l1/revoke') {
          links.first['active'] = false;
          return _json(links.first);
        }
        return null;
      };
      final shared = <String>[];
      await _pump(
        tester,
        api,
        const SummaryReportScreen(),
        overrides: [
          pdfSharerProvider.overrideWithValue(
            (path, name) async => shared.add(name),
          ),
        ],
      );
      expect(find.text('Median glukosa puasa'), findsOneWidget);
      expect(find.text('128 mg/dL'), findsOneWidget);
      expect(find.text('Hari aktif'), findsNothing);
      await tester.tap(find.text('Buat tautan dan kode QR'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Siapa pun yang memegang tautan ini'),
        findsOneWidget,
      );
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(api.count('/api/me/share-links', 'POST'), 0);
      await tester.tap(find.text('Buat tautan dan kode QR'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Buat tautan'));
      await tester.pumpAndSettle();
      expect(api.body('/api/me/share-links'), {
        'periodDays': 30,
        'hours': 72,
        'confirm': true,
      });
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Cabut'), findsOneWidget);
      await tester.tap(find.text('Cabut'));
      await tester.pumpAndSettle();
      expect(api.count('/api/me/share-links/l1/revoke', 'POST'), 1);
      expect(find.byType(QrImageView), findsNothing);
    },
  );

  testWidgets('S-7: the PDF is a real PDF document built from the summary', (
    tester,
  ) async {
    final bytes = await tester.runAsync(
      () async => buildSummaryPdf(
        ReportSummary.fromJson(_summary()),
        theme: await pdfTheme(),
      ),
    );
    expect(bytes, isNotNull);
    expect(String.fromCharCodes(bytes!.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(2000));
  });

  testWidgets(
    'U-8: "Sudah" on a medication notification records the intake for that exact occurrence',
    (tester) async {
      final api = _Api();
      api.extra = (r) => r.url.path == '/api/me/medications/reg1/intakes'
          ? _json({'id': 'i1'}, 201)
          : null;
      late WidgetRef captured;
      await _pump(
        tester,
        api,
        Consumer(
          builder: (_, ref, _) {
            captured = ref;
            return const SizedBox();
          },
        ),
        overrides: [syncControllerProvider.overrideWith(SyncController.new)],
      );
      final ref = MedicationRef.parse(
        jsonEncode(
          const MedicationRef(
            'reg1',
            'sch1',
            '2026-11-12T00:00:00.000Z',
          ).toJson(),
        ),
      )!;
      final text = await tester.runAsync(
        () => confirmMedicationFromNotification(captured, ref),
      );
      expect(text, 'Obat tercatat sudah diminum.');
      final b = api.body('/api/me/medications/reg1/intakes');
      expect(
        [b['scheduleId'], b['scheduledAt'], b['status']],
        ['sch1', '2026-11-12T00:00:00.000Z', 'taken'],
      );
      expect(MedicationRef.parse('{"type":"other"}'), isNull);
      expect(MedicationRef.parse(null), isNull);
    },
  );

  test(
    'U-3: the high-contrast palette uses primary text for secondary text and borders',
    () {
      final hc = AppPalette.light.highContrast();
      expect(hc.textSecondary, AppPalette.light.textPrimary);
      expect(hc.border, AppPalette.light.textSecondary);
      expect(hc.brand, AppPalette.light.brand);
    },
  );
}
