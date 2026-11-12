import 'dart:convert';
import 'dart:io';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/offline/offline_queue.dart';
import 'package:app/core/offline/sync_controller.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/core/voice/voice_input.dart';
import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/auth/data/session_user.dart';
import 'package:app/features/cgm/cgm.dart';
import 'package:app/features/coach/data/conversation_models.dart';
import 'package:app/features/companion/companion.dart';
import 'package:app/features/education/education.dart';
import 'package:app/features/export/data/data_exporter.dart';
import 'package:app/features/guest/guest_mode.dart';
import 'package:app/features/nutrition/data/nutrition_models.dart';
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
  http.Request last(String path, String method) =>
      seen.lastWhere((r) => r.url.path == path && r.method == method);
}

class _Voice implements VoiceInput {
  void Function(String, bool)? onText;
  void Function(VoiceFailure)? onError;
  bool stopped = false;
  @override
  Future<bool> start({
    required void Function(String text, bool done) onText,
    required void Function(VoiceFailure failure) onError,
  }) async {
    this.onText = onText;
    this.onError = onError;
    return true;
  }

  @override
  Future<void> stop() async => stopped = true;
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _Api api,
  Widget home, {
  List<Override> overrides = const [],
  MemoryKeyValueStore? store,
  bool signedIn = true,
  List<RouteBase> routes = const [],
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: home),
      ),
      ...routes,
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        if (signedIn) authControllerProvider.overrideWith(_Auth.new),
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

Map<String, dynamic> _module(String key, String status) => {
  'key': key,
  'version': 1,
  'title': 'Gula darah rendah (hipoglikemia)',
  'summary': 'Mengenali tanda gula darah rendah.',
  'topics': ['glukosa'],
  'readMinutes': 5,
  'reviewStatus': status,
  'reviewedAt': null,
};

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets(
    'K-4: daftar modul menandai draf; isi modul tampil per bagian dengan catatan dan versi',
    (tester) async {
      _tall(tester);
      final api = _Api();
      api.extra = (r) => switch (r.url.path) {
        '/api/education/modules' => _json({
          'items': [_module('hipoglikemia', 'DRAFT')],
          'includesDrafts': true,
        }),
        '/api/education/modules/hipoglikemia' => _json({
          ..._module('hipoglikemia', 'DRAFT'),
          'authoredOn': '2026-11-12',
          'reviewedBy': null,
          'notice':
              'Draf: belum ditinjau klinisi. Bacaan umum, bukan pengganti saran tenaga kesehatanmu.',
          'sections': [
            {
              'heading': 'Tandanya',
              'paragraphs': ['Gemetar, berkeringat.'],
              'bullets': [],
            },
            {
              'heading': 'Segera cari bantuan bila',
              'paragraphs': [],
              'bullets': ['Pingsan atau kejang'],
            },
          ],
        }),
        _ => null,
      };
      await _pump(
        tester,
        api,
        const EducationListScreen(),
        routes: [
          GoRoute(
            path: '/learn/:key',
            builder: (_, s) =>
                EducationModuleScreen(moduleKey: s.pathParameters['key']!),
          ),
        ],
      );
      expect(find.text('Gula darah rendah (hipoglikemia)'), findsOneWidget);
      expect(find.text('DRAF · menunggu tinjauan klinisi'), findsOneWidget);
      await tester.tap(find.text('Gula darah rendah (hipoglikemia)'));
      await tester.pumpAndSettle();
      expect(find.text('Segera cari bantuan bila'), findsOneWidget);
      expect(find.text('Pingsan atau kejang'), findsOneWidget);
      expect(
        find.textContaining(
          'Versi 1 · ditulis 2026-11-12 · belum ditinjau klinisi',
        ),
        findsOneWidget,
      );
    },
  );

  test('K-4: jawaban keselamatan memuat bagian edukasi', () {
    final part = ChatPart.fromJson({
      'type': 'education',
      'items': [
        {
          'key': 'obat-bertanya-dokter',
          'title': 'Obat: kapan bertanya ke dokter',
          'readMinutes': 3,
          'reviewStatus': 'DRAFT',
        },
      ],
    });
    expect(part, isA<EducationPart>());
    expect((part! as EducationPart).items.single.reviewed, isFalse);
  });

  testWidgets('K-4: tautan modul di Asisten membuka modul', (tester) async {
    final api = _Api();
    var opened = false;
    await _pump(
      tester,
      api,
      EducationLinks(
        items: [EducationItem.fromJson(_module('hipoglikemia', 'REVIEWED'))],
      ),
      routes: [
        GoRoute(
          path: '/learn/:key',
          builder: (_, s) {
            opened = s.pathParameters['key'] == 'hipoglikemia';
            return const SizedBox();
          },
        ),
      ],
    );
    expect(find.text('Baca: Gula darah rendah (hipoglikemia)'), findsOneWidget);
    expect(find.text('Modul edukasi · 5 menit'), findsOneWidget);
    await tester.tap(find.text('Baca: Gula darah rendah (hipoglikemia)'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });

  test('K-7: hidangan kurasi membawa label sumber dan porsi umum', () {
    final r = ReferenceFood.fromJson({
      'code': 'CUR-001',
      'name': 'Nasi goreng telur',
      'provenance': 'Kurasi beOkay · dari bahan TKPI',
      'source': 'Kurasi beOkay (resep standar dari bahan TKPI)',
      'completeness': 'COMPLETE',
      'verification': 'curated',
      'serving': {'minGrams': 200, 'typicalGrams': 290, 'maxGrams': 400},
      'per100g': {
        'calories': 187.8,
        'carbohydrates': 28.7,
        'protein': 4.6,
        'fat': 5.6,
        'fiber': 0.2,
      },
    });
    expect(r.curated, isTrue);
    expect(r.servingLabel, 'Porsi umum 290 g (200–400 g)');
    final tkpi = ReferenceFood.fromJson({
      'code': 'AP001',
      'name': 'Nasi',
      'provenance': 'Tabel Komposisi Pangan Indonesia',
      'source': 'Tabel Komposisi Pangan Indonesia',
      'completeness': 'COMPLETE',
      'per100g': {'calories': 180},
    });
    expect([tkpi.curated, tkpi.servingLabel], [false, null]);
  });

  testWidgets(
    'K-3: impor CSV mengirim text/csv, menangani tanggal ambigu, dan menampilkan ringkasan deskriptif',
    (tester) async {
      _tall(tester);
      final api = _Api();
      var attempts = 0;
      api.extra = (r) {
        if (r.url.path == '/api/me/cgm/imports' && r.method == 'POST') {
          attempts++;
          if (r.url.queryParameters['dateOrder'] == 'auto') {
            return _json({
              'error': {
                'code': 'CGM_DATE_ORDER_AMBIGUOUS',
                'message': 'Urutan tanggal tidak bisa dipastikan.',
              },
            }, 422);
          }
          return _json({
            'id': 'i1',
            'fileName': 'libre.csv',
            'rowsAccepted': 96,
            'rowsDuplicate': 0,
            'rowsSkipped': 2,
            'periodStart': '2026-11-10T00:00:00Z',
            'periodEnd': '2026-11-11T00:00:00Z',
            'createdAt': '2026-11-12T00:00:00Z',
          }, 201);
        }
        if (r.url.path == '/api/me/cgm/imports') return _json({'items': []});
        if (r.url.path == '/api/me/cgm/summary') {
          return _json({
            'period': {'start': '2026-10-30', 'end': '2026-11-12'},
            'days': 14,
            'readings': 96,
            'kindUsed': 'HISTORIC',
            'coveragePct': 7.1,
            'sufficient': false,
            'meanMgDl': 154,
            'meanMmolL': 8.5,
            'glucoseUnit': 'mg/dL',
            'bands': {
              'veryLow': 0,
              'low': 20,
              'inRange': 40,
              'high': 20,
              'veryHigh': 20,
            },
            'limitations': [
              'Data terekam kurang dari 70% periode; ringkasan bisa tidak mewakili.',
            ],
            'notice':
                'Ringkasan deskriptif dari sensor. Bukan saran dosis atau pengobatan; bicarakan hasilnya dengan dokter.',
          });
        }
        return null;
      };
      await _pump(
        tester,
        api,
        const CgmScreen(),
        overrides: [
          csvPickerProvider.overrideWithValue(
            () async => (name: 'libre.csv', text: 'Device Timestamp\n'),
          ),
        ],
      );
      expect(find.text('40%'), findsNWidgets(2));
      expect(find.text('154 mg/dL'), findsOneWidget);
      expect(find.textContaining('Bukan saran dosis'), findsOneWidget);
      expect(find.textContaining('kurang dari 70%'), findsOneWidget);
      await tester.tap(find.text('Pilih berkas CSV'));
      await tester.pumpAndSettle();
      expect(find.text('Bagaimana tanggal ditulis?'), findsOneWidget);
      await tester.tap(find.text('Hari-bulan'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      final sent = api.last('/api/me/cgm/imports', 'POST');
      expect(sent.headers['content-type'], startsWith('text/csv'));
      expect(sent.url.queryParameters['dateOrder'], 'DMY');
      expect(find.textContaining('96 bacaan diterima'), findsOneWidget);
    },
  );

  testWidgets(
    'K-8: membuat tautan pendamping setelah konfirmasi; persetujuan yang belum ada diarahkan',
    (tester) async {
      _tall(tester);
      final api = _Api();
      var consent = false;
      api.extra = (r) {
        if (r.url.path == '/api/me/companions' && r.method == 'POST') {
          if (!consent) {
            return _json({
              'error': {'code': 'CONSENT_REQUIRED', 'message': 'x'},
            }, 403);
          }
          return _json({
            'id': 'c1',
            'label': 'Anak',
            'active': true,
            'viewCount': 0,
            'expiresAt': '2027-02-10T00:00:00Z',
            'createdAt': '2026-11-12T00:00:00Z',
            'lastViewedAt': null,
            'url': 'http://test/c/abc',
          }, 201);
        }
        if (r.url.path == '/api/me/companions') return _json({'items': []});
        return null;
      };
      await _pump(tester, api, const CompanionScreen());
      await tester.enterText(find.byType(TextField), 'Anak');
      await tester.tap(find.text('Buat tautan pendamping'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Buat tautan'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Berbagi ringkasan mingguan dengan pendamping'),
        findsOneWidget,
      );
      expect(find.text('Buka persetujuan'), findsOneWidget);
      consent = true;
      await tester.enterText(find.byType(TextField), 'Anak');
      await tester.tap(find.text('Buat tautan pendamping'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Buat tautan'));
      await tester.pumpAndSettle();
      final body =
          jsonDecode(api.last('/api/me/companions', 'POST').body) as Map;
      expect(body, {'label': 'Anak', 'days': 90, 'confirm': true});
      expect(find.text('http://test/c/abc'), findsOneWidget);
    },
  );

  testWidgets(
    'D-6: ekspor FHIR mengunduh bundle dan menyerahkannya ke lembar bagikan',
    (tester) async {
      final api = _Api();
      api.extra = (r) => r.url.path == '/api/me/export/fhir'
          ? _json({
              'resourceType': 'Bundle',
              'type': 'collection',
              'timestamp': '2026-11-12T00:00:00Z',
              'entry': [{}, {}, {}],
            })
          : null;
      String? shared;
      final n = await tester.runAsync(
        () => exportFhir(
          api.client,
          share: (path, name) async => shared = name,
          tempDir: () async => Directory.systemTemp,
        ),
      );
      expect(n, 3);
      expect(shared, 'beokay-fhir-2026-11-12.json');
    },
  );

  testWidgets(
    'U-2: tombol mikrofon mengisi teks dari dikte di perangkat dan menjelaskan bila tidak tersedia',
    (tester) async {
      final api = _Api();
      final voice = _Voice();
      final controller = TextEditingController(text: 'tadi');
      addTearDown(controller.dispose);
      await _pump(
        tester,
        api,
        MicButton(controller: controller, domain: 'assistant'),
        overrides: [voiceInputProvider.overrideWithValue(voice)],
      );
      expect(
        find.byTooltip('Dikte dengan suara (diproses di perangkat)'),
        findsOneWidget,
      );
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      voice.onText!('siang makan nasi goreng', false);
      await tester.pump();
      expect(controller.text, 'tadi siang makan nasi goreng');
      expect(find.byTooltip('Selesai bicara'), findsOneWidget);
      voice.onText!('siang makan nasi goreng dan es teh', true);
      await tester.pump();
      expect(controller.text, 'tadi siang makan nasi goreng dan es teh');
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      voice.onError!(VoiceFailure.unavailable);
      await tester.pump();
      expect(
        find.textContaining('Dikte di perangkat belum tersedia'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'U-4: mode coba menyimpan catatan hanya di perangkat; setelah masuk, catatan dipindahkan lewat antrean sinkron',
    (tester) async {
      _tall(tester);
      final store = MemoryKeyValueStore();
      final api = _Api();
      await _pump(
        tester,
        api,
        const GuestHomeScreen(),
        store: store,
        signedIn: false,
        routes: [
          GoRoute(path: '/welcome', builder: (_, _) => const SizedBox()),
        ],
      );
      expect(find.textContaining('Sisa 7 hari'), findsOneWidget);
      await tester.tap(find.text('+ Glukosa'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '132');
      await tester.tap(find.text('Simpan di ponsel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+ Makan'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Nasi uduk');
      await tester.tap(find.text('Sarapan'));
      await tester.tap(find.text('Simpan di ponsel'));
      await tester.pumpAndSettle();
      expect(find.text('Glukosa 132.0 mg/dL'), findsNothing);
      expect(find.text('Glukosa 132 mg/dL'), findsOneWidget);
      expect(find.text('Nasi uduk'), findsOneWidget);
      expect(api.seen, isEmpty);
      final guest = await OfflineQueue(store, guestAccount).load();
      expect(guest.map((o) => o.domain), ['glucose', 'meal']);
      expect(guest.first.payload, containsPair('mealContext', 'fasting'));
      expect((guest.last.payload['items'] as List).single, {
        'name': 'Nasi uduk',
        'quantity': 1,
        'unit': 'portion',
      });

      await tester.pumpWidget(const SizedBox());
      final api2 = _Api();
      api2.extra = (r) => r.url.path == '/api/me/sync/operations'
          ? _json({
              'items': [
                for (final op in (jsonDecode(r.body)['operations'] as List))
                  {'operationId': op['operationId'], 'status': 'SYNCED'},
              ],
            })
          : null;
      final c = await _pump(
        tester,
        api2,
        const GuestImportCard(),
        store: store,
        overrides: [syncControllerProvider.overrideWith(SyncController.new)],
      );
      expect(
        find.text('Ada 2 catatan dari mode coba di ponsel ini'),
        findsOneWidget,
      );
      await tester.tap(find.text('Pindahkan 2 catatan'));
      await tester.pumpAndSettle();
      expect(await OfflineQueue(store, guestAccount).load(), isEmpty);
      final mine = await OfflineQueue(store, 'u1').load();
      final sent = api2.seen
          .where((r) => r.url.path == '/api/me/sync/operations')
          .length;
      expect(mine.length + sent, greaterThanOrEqualTo(1));
      expect(c.read(guestControllerProvider).records, isEmpty);
      expect(
        find.text('Ada 2 catatan dari mode coba di ponsel ini'),
        findsNothing,
      );
    },
  );

  test('U-4: masa coba 7 hari dihitung dari awal mode coba', () {
    final start = DateTime.utc(2026, 11, 1);
    final s = GuestState(loaded: true, startedAt: start);
    expect(s.daysLeft(start.add(const Duration(hours: 1))), 7);
    expect(s.daysLeft(start.add(const Duration(days: 6, hours: 1))), 1);
    expect(s.expired(start.add(const Duration(days: 7))), isTrue);
    expect(const GuestState(loaded: true).expired(DateTime.utc(2030)), isFalse);
  });
}
