import 'dart:convert';

import 'package:app/core/analytics/usage_tracker.dart';
import 'package:app/core/network/api_client.dart';
import 'package:app/core/offline/offline_queue.dart';
import 'package:app/core/offline/sync_controller.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/core/widgets/app_text_field.dart';
import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/auth/data/session_user.dart';
import 'package:app/features/clinical/application/clinical_controller.dart';
import 'package:app/features/clinical/data/clinical_models.dart';
import 'package:app/features/clinical/data/clinical_repository.dart';
import 'package:app/features/clinical/presentation/clinical_forms.dart';
import 'package:app/features/clinical/presentation/clinical_screen.dart';
import 'package:app/features/coaching/application/coaching_controller.dart';
import 'package:app/features/coaching/data/coaching_repository.dart';
import 'package:app/features/coaching/presentation/reflection_screen.dart';
import 'package:app/features/consent/application/consent_controller.dart';
import 'package:app/features/consent/data/consent_models.dart';
import 'package:app/features/glucose/application/glucose_controller.dart';
import 'package:app/features/glucose/data/glucose_models.dart';
import 'package:app/features/glucose/presentation/glucose_detail_screen.dart';
import 'package:app/features/glucose/presentation/glucose_form_screen.dart';
import 'package:app/features/quick_record/application/quick_record_controller.dart';
import 'package:app/features/quick_record/data/quick_record_repository.dart';
import 'package:app/features/quick_record/presentation/quick_repeat_card.dart';
import 'package:app/features/reports/presentation/report_screen.dart';
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

class _Consent extends ConsentController {
  _Consent(this.analytics);
  final bool analytics;
  @override
  Future<ConsentOverview?> build() async => ConsentOverview.fromJson({
    'policyVersion': '1.0',
    'purposes': [
      for (final p in [
        'health_data_processing',
        'descriptive_summaries',
        'product_analytics',
      ])
        {
          'purpose': p,
          'required': p != 'product_analytics',
          'status': p == 'product_analytics' && !analytics
              ? 'not_given'
              : 'granted',
          'policyVersion': '1.0',
          'grantedAt': '2026-11-01T00:00:00Z',
          'withdrawnAt': null,
        },
    ],
    'history': <dynamic>[],
  });
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
  bool analytics = true,
  List<Override> overrides = const [],
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: home),
      ),
      GoRoute(
        path: '/meals/:id',
        builder: (_, s) => Text('Detail ${s.pathParameters['id']}'),
      ),
      GoRoute(path: '/clinical', builder: (_, _) => const Text('Klinis')),
    ],
  );
  addTearDown(router.dispose);
  final store = MemoryKeyValueStore();
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        authControllerProvider.overrideWith(_Auth.new),
        consentControllerProvider.overrideWith(() => _Consent(analytics)),
        apiClientProvider.overrideWithValue(api.client),
        keyValueStoreProvider.overrideWithValue(store),
        ...overrides,
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

Map<String, dynamic> _glucose({
  num value = 55,
  String unit = 'mg/dL',
  Map<String, dynamic>? alert,
}) => {
  'id': 'g1',
  'originalValue': value,
  'originalUnit': unit,
  'displayValue': value,
  'displayUnit': 'mg/dL',
  'valueMgDl': value,
  'measuredAt': DateTime.now()
      .subtract(const Duration(minutes: 5))
      .toUtc()
      .toIso8601String(),
  'localDate': '2026-11-12',
  'localTime': '07:10',
  'timezone': 'Asia/Jakarta',
  'version': 1,
  'mealContext': 'fasting',
  'qualityStatus': 'user_reported',
  'alert': alert,
};

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets(
    'U-1: repeating a frequent meal is one tap, uses the template and current time, and is counted only with analytics consent',
    (tester) async {
      _tall(tester);
      final api = _Api();
      api.extra = (r) {
        if (r.url.path == '/api/me/quick-record/suggestions') {
          return _json({
            'meals': [
              {
                'key': 'k1',
                'title': 'Nasi uduk, Teh manis',
                'category': 'breakfast',
                'count': 3,
                'lastAt': '2026-11-11T00:00:00Z',
                'nutritionKnown': false,
                'template': {
                  'category': 'breakfast',
                  'items': [
                    {
                      'foodId': 'f1',
                      'name': 'Nasi uduk',
                      'quantity': 1,
                      'unit': 'portion',
                      'grams': 150,
                      'gramsBasis': 'user_estimate',
                    },
                    {
                      'name': 'Teh manis',
                      'quantity': 1,
                      'unit': 'piece',
                      'grams': null,
                      'gramsBasis': null,
                    },
                  ],
                },
              },
            ],
            'activities': [
              {
                'key': 'a1',
                'title': 'Jalan kaki 20 menit',
                'count': 2,
                'lastAt': '2026-11-11T00:00:00Z',
                'template': {
                  'activityType': 'walking',
                  'durationMinutes': 20,
                  'reportedIntensity': 'light',
                },
              },
            ],
          });
        }
        if (r.url.path == '/api/me/meals' && r.method == 'POST') {
          final b = jsonDecode(r.body) as Map<String, dynamic>;
          return _json({
            'id': b['id'],
            'category': 'breakfast',
            'consumedAt': b['consumedAt'],
            'localDate': '2026-11-12',
            'localTime': '07:00',
            'timezone': 'Asia/Jakarta',
            'notes': null,
            'version': 1,
            'archivedAt': null,
            'captureMethod': 'manual',
            'createdAt': b['consumedAt'],
            'updatedAt': b['consumedAt'],
            'items': <dynamic>[],
            'totals': {
              for (final k in [
                'calories',
                'carbohydrates',
                'protein',
                'fat',
                'fiber',
              ])
                k: {
                  'value': null,
                  'coverage': 'UNKNOWN',
                  'knownItems': 0,
                  'totalItems': 2,
                },
            },
          }, 201);
        }
        return null;
      };
      final c = await _pump(
        tester,
        api,
        const SingleChildScrollView(child: QuickRepeatCard()),
      );
      expect(find.text('Sering dicatat'), findsOneWidget);
      expect(
        find.text('Sarapan · 3× dalam 30 hari · sebagian gizi belum ada'),
        findsOneWidget,
      );
      expect(find.text('Jalan kaki 20 menit'), findsOneWidget);
      await tester.tap(find.text('Nasi uduk, Teh manis'));
      await tester.pumpAndSettle();
      final body = api.body('/api/me/meals');
      expect(body['category'], 'breakfast');
      expect((body['items'] as List).first, containsPair('foodId', 'f1'));
      expect(
        DateTime.parse(
              body['consumedAt'] as String,
            ).difference(DateTime.now()).inMinutes.abs() <
            2,
        isTrue,
      );
      expect(
        find.text('Tersimpan: Sarapan · Nasi uduk, Teh manis'),
        findsOneWidget,
      );
      final pending = c
          .read(usageTrackerProvider)
          .pending
          .map((e) => e.type)
          .toList();
      expect(pending, containsAll(['quick_repeat_used', 'form_saved']));
      expect(
        c
            .read(usageTrackerProvider)
            .pending
            .firstWhere((e) => e.type == 'form_saved')
            .meta['via'],
        'quick',
      );
    },
  );

  testWidgets(
    'D-1: without analytics consent the tracker records nothing; with consent a batch carries only types and timings',
    (tester) async {
      final api = _Api();
      api.extra = (r) => r.url.path == '/api/me/usage-events'
          ? _json({'accepted': 1, 'dropped': 0, 'recorded': true}, 202)
          : null;
      var c = await _pump(tester, api, const SizedBox(), analytics: false);
      c
          .read(usageTrackerProvider)
          .formSaved('glucose', const Duration(seconds: 4));
      expect(c.read(usageTrackerProvider).pending, isEmpty);
      await tester.pumpWidget(const SizedBox());
      c = await _pump(tester, api, const SizedBox());
      final t = c.read(usageTrackerProvider);
      await tester.pumpAndSettle();
      t.formSaved('glucose', const Duration(seconds: 4));
      await t.flush();
      final sent = api.body('/api/me/usage-events');
      expect(sent['appVersion'], isNotEmpty);
      final e = (sent['events'] as List).single as Map;
      expect(e['type'], 'form_saved');
      expect(e['meta'], {'via': 'form', 'durationMs': 4000});
    },
  );

  testWidgets(
    'K-10: the glucose form warns while typing a value below 70 or from 300 mg/dL, in either unit',
    (tester) async {
      _tall(tester);
      final api = _Api();
      final record = GlucoseRecord.fromJson(_glucose(value: 110));
      await _pump(tester, api, GlucoseFormScreen(initial: record));
      Finder field() => find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is AppTextField && w.label == 'Nilai pengukuran',
        ),
        matching: find.byType(TextFormField),
      );
      expect(find.text('Angka ini di bawah 70 mg/dL'), findsNothing);
      await tester.enterText(field(), '55');
      await tester.pump();
      expect(find.text('Angka ini di bawah 70 mg/dL'), findsOneWidget);
      await tester.enterText(field(), '320');
      await tester.pump();
      expect(find.text('Angka ini 300 mg/dL atau lebih'), findsOneWidget);
      await tester.tap(find.text('mmol/L'));
      await tester.pump();
      expect(find.text('Angka ini 300 mg/dL atau lebih'), findsOneWidget);
      await tester.enterText(field(), '6,1');
      await tester.pump();
      expect(find.textContaining('Angka ini'), findsNothing);
      await tester.enterText(field(), '3,5');
      await tester.pump();
      expect(find.text('Angka ini di bawah 70 mg/dL'), findsOneWidget);
      expect(glucoseAlertFor(16.7, 'mmol/L')?.level, 'HIGH');
      expect(glucoseAlertFor(70, 'mg/dL'), isNull);
    },
  );

  testWidgets(
    'U-5 + K-10: the glucose detail shows the server alert and a neutral comparison with own records',
    (tester) async {
      _tall(tester);
      final api = _Api();
      final rec = GlucoseRecord.fromJson(
        _glucose(
          alert: {
            'level': 'LOW',
            'title': 'Angka ini di bawah 70 mg/dL',
            'message': 'Hubungi 119 bila tidak membaik.',
          },
        ),
      );
      await _pump(
        tester,
        api,
        const GlucoseDetailScreen(id: 'g1'),
        overrides: [
          glucoseProvider.overrideWith((ref, id) async => rec),
          glucoseRevisionsProvider.overrideWith(
            (ref, id) async => <Map<String, dynamic>>[],
          ),
          glucoseContextProvider.overrideWith(
            (ref, id) async => GlucoseContext.fromJson({
              'line':
                  'Lebih rendah dari median puasa 14 harimu: 128 mg/dL dari 9 catatan.',
              'comparison': {'comparison': 'LOWER'},
              'previous': {
                'value': 130,
                'localDate': '2026-11-11',
                'localTime': '06:50',
              },
              'displayUnit': 'mg/dL',
              'neutralNote':
                  'Perbandingan ini hanya dengan catatanmu sendiri dan bukan penilaian klinis.',
            }),
          ),
        ],
      );
      expect(find.text('Angka ini di bawah 70 mg/dL'), findsOneWidget);
      expect(find.text('DIBANDINGKAN CATATANMU'), findsOneWidget);
      expect(
        find.text(
          'Lebih rendah dari median puasa 14 harimu: 128 mg/dL dari 9 catatan.',
        ),
        findsOneWidget,
      );
      expect(find.text('130 mg/dL · 2026-11-11 · 06:50'), findsOneWidget);
    },
  );

  testWidgets(
    'K-2: the clinical overview shows values as-is with descriptive change, and the blood pressure form checks the pair',
    (tester) async {
      _tall(tester);
      final api = _Api();
      api.extra = (r) => r.url.path == '/api/me/vitals' && r.method == 'POST'
          ? _json({
              ...jsonDecode(r.body) as Map<String, dynamic>,
              'label': 'Tekanan darah',
              'localDate': '2026-11-12',
              'localTime': '08:00',
              'version': 1,
              'archivedAt': null,
              'notes': null,
              'value2': 82,
            }, 201)
          : null;
      final summary = ClinicalSummary.fromJson({
        'vitals': [
          {
            'kind': 'weight',
            'label': 'Berat badan',
            'latest': {
              'id': 'v1',
              'kind': 'weight',
              'label': 'Berat badan',
              'value': 72.4,
              'value2': null,
              'unit': 'kg',
              'measuredAt': '2026-11-11T01:00:00Z',
              'localDate': '2026-11-11',
              'localTime': '08:00',
              'notes': null,
              'version': 2,
              'archivedAt': null,
            },
            'change': {'difference': -2.1, 'direction': 'DOWN'},
          },
          {
            'kind': 'blood_pressure',
            'label': 'Tekanan darah',
            'latest': null,
            'change': null,
          },
        ],
        'labs': [
          {
            'test': 'hba1c',
            'label': 'HbA1c',
            'latest': {
              'id': 'l1',
              'test': 'hba1c',
              'label': 'HbA1c',
              'value': 7.4,
              'unit': '%',
              'sampledAt': '2026-08-01',
              'labName': null,
              'source': 'lab_report',
              'notes': null,
              'version': 1,
              'archivedAt': null,
            },
            'change': null,
          },
        ],
        'hba1c': {
          'status': 'DUE',
          'lastSampledAt': '2026-08-01',
          'dueOn': '2026-10-30',
          'daysSince': 103,
        },
        'notice': 'Angka ditampilkan apa adanya, tanpa penilaian klinis.',
      });
      await _pump(
        tester,
        api,
        const ClinicalScreen(),
        overrides: [
          clinicalSummaryProvider.overrideWith((ref) async => summary),
        ],
      );
      expect(find.text('72,4 kg'), findsOneWidget);
      expect(
        find.textContaining('Turun 2,1 kg dari sebelumnya'),
        findsOneWidget,
      );
      expect(find.textContaining('sudah 103 hari'), findsOneWidget);
      expect(find.text('7,4 %'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await _pump(
        tester,
        api,
        const VitalFormScreen(kind: 'blood_pressure'),
        overrides: [
          clinicalRepositoryProvider.overrideWith(
            (ref) =>
                ClinicalRepository(api.client, isCurrentAccount: () => true),
          ),
        ],
      );
      Finder field(String label) => find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is AppTextField && w.label == label,
        ),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(field('Sistolik (angka atas)'), '80');
      await tester.enterText(field('Diastolik (angka bawah)'), '120');
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(
        find.text('Angka bawah harus lebih kecil dari angka atas.'),
        findsOneWidget,
      );
      await tester.enterText(field('Sistolik (angka atas)'), '128');
      await tester.enterText(field('Diastolik (angka bawah)'), '82');
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      final b = api.body('/api/me/vitals');
      expect(
        [b['kind'], b['value'], b['value2'], b['unit']],
        ['blood_pressure', 128, 82, 'mmHg'],
      );
    },
  );

  testWidgets(
    'K-5 + K-6: a raised target is opt-in, a strategy for a chosen barrier becomes part of the check-in, last week\'s strategy is reviewed',
    (tester) async {
      _tall(tester);
      final api = _Api();
      api.extra = (r) {
        if (r.url.path == '/api/me/coaching/checkins' && r.method == 'GET') {
          return _json({
            'consentRequired': false,
            'weekStart': '2026-11-08',
            'weekEnd': '2026-11-14',
            'done': null,
            'summary': {'recordedDays': 6, 'totalDays': 7},
            'goals': <dynamic>[],
            'actions': {
              'observed': 0,
              'confirmed': 0,
              'notObserved': 0,
              'planned': 0,
              'fromAssistant': 0,
              'items': <dynamic>[],
            },
            'positives': [
              'Strategi “Pasang satu pengingat” kamu jalankan 3 hari',
            ],
            'adjustments': [
              {
                'goalId': 'g1',
                'title': 'Aktif 150 menit',
                'goalType': 'activity_minutes',
                'fromTarget': 150,
                'toTarget': 165,
                'expectedVersion': 2,
                'basis': 'Tercapai di 3 dari 4 minggu terakhir.',
                'direction': 'UP',
              },
            ],
            'strategies': {
              'reviewStatus': 'DRAFT_NOT_CLINICALLY_REVIEWED',
              'byBarrier': {
                'TIME': [
                  {
                    'key': 'TIME_SPLIT',
                    'title': 'Bagi jadi potongan 10 menit',
                    'detail': 'Beberapa kali 10 menit.',
                  },
                  {
                    'key': 'TIME_ANCHOR',
                    'title': 'Tempelkan ke kegiatan rutin',
                    'detail': 'Setelah makan siang.',
                  },
                ],
                'ENERGY': [
                  {
                    'key': 'ENERGY_LIGHT',
                    'title': 'Pilih versi yang ringan',
                    'detail': 'Jalan santai.',
                  },
                ],
              },
            },
            'previousStrategy': {
              'title': 'Pasang satu pengingat',
              'barrierLabel': 'Lupa',
              'confirmedDays': 3,
              'days': 7,
            },
            'streak': 1,
            'memoryAvailable': false,
            'preferredSlot': null,
          });
        }
        if (r.url.path == '/api/me/coaching/checkins') {
          return _json({
            'checkin': {'id': 'c1', 'weekStart': '2026-11-08'},
            'recognition': ['Refleksi mingguan selesai'],
            'replayed': false,
          }, 201);
        }
        return null;
      };
      await _pump(
        tester,
        api,
        const ReflectionScreen(),
        overrides: [
          coachingRepositoryProvider.overrideWithValue(
            CoachingRepository(api.client, isCurrentAccount: () => true),
          ),
        ],
      );
      expect(find.text('CARA YANG KAMU COBA'), findsOneWidget);
      expect(
        find.text('Kamu jalankan 3 dari 7 hari · hambatan lupa.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Waktu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();
      expect(find.text('Naikkan target: 150 → 165 menit'), findsOneWidget);
      expect(find.text('Cara mengatasi: waktu'), findsOneWidget);
      expect(find.text('Pilih versi yang ringan'), findsNothing);
      expect(
        find.text('Daftar cara ini masih menunggu tinjauan tenaga kesehatan.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Bagi jadi potongan 10 menit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aktif 150 menit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan refleksi'));
      await tester.pumpAndSettle();
      final b = api.body('/api/me/coaching/checkins');
      expect(b['strategy'], {'barrier': 'TIME', 'key': 'TIME_SPLIT'});
      expect(b['adjustments'], [
        {'goalId': 'g1', 'toTarget': 165.0},
      ]);
    },
  );

  testWidgets(
    'D-5: a report sends category, message and contact choice, and shows the safety message the server returns',
    (tester) async {
      _tall(tester);
      final api = _Api();
      api.extra = (r) => r.url.path == '/api/me/reports'
          ? _json({
              'id': 'r1',
              'category': 'adverse_event',
              'emailed': true,
              'createdAt': '2026-11-12T00:00:00Z',
              'message':
                  'Terima kasih. Bila kamu merasa tidak sehat sekarang, hubungi 119.',
            }, 201)
          : null;
      await _pump(tester, api, const ReportScreen());
      expect(find.text('Dalam keadaan darurat'), findsOneWidget);
      await tester.tap(find.text('Kirim laporan'));
      await tester.pumpAndSettle();
      expect(
        find.text('Tuliskan minimal satu kalimat singkat.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Kejadian tidak diinginkan'));
      await tester.enterText(
        find.byType(TextField),
        'Pusing setelah jalan pagi.',
      );
      await tester.tap(find.text('Boleh dihubungi lewat surel akun'));
      await tester.tap(find.text('Kirim laporan'));
      await tester.pumpAndSettle();
      final b = api.body('/api/me/reports');
      expect(
        [b['category'], b['message'], b['contactOk']],
        ['adverse_event', 'Pusing setelah jalan pagi.', true],
      );
      expect(
        find.text(
          'Terima kasih. Bila kamu merasa tidak sehat sekarang, hubungi 119.',
        ),
        findsOneWidget,
      );
    },
  );

  test(
    'Offline queue labels include the new domains and suggestions parse',
    () {
      final op = QueuedOperation(
        operationId: 'o',
        domain: 'vital',
        recordId: 'r',
        operationType: 'create',
        payload: const {},
        createdAt: DateTime(2026),
      );
      expect(op.label, 'Ukuran tubuh');
      expect(
        QuickSuggestions.fromJson({'meals': [], 'activities': []}).isEmpty,
        isTrue,
      );
      expect(quickSuggestionsProvider, isNotNull);
      expect(syncControllerProvider, isNotNull);
      expect(fmtNum(7.25), '7,25');
    },
  );
}
