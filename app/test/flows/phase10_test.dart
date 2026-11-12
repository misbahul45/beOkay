import 'dart:convert';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/features/coach/data/conversation_models.dart';
import 'package:app/features/coach/presentation/chat_parts.dart';
import 'package:app/features/coaching/application/coaching_controller.dart';
import 'package:app/features/coaching/data/coaching_repository.dart';
import 'package:app/features/coaching/presentation/reflection_screen.dart';
import 'package:app/features/memory/application/memory_controller.dart';
import 'package:app/features/memory/data/memory_repository.dart';
import 'package:app/features/memory/presentation/memory_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _pump(
  WidgetTester tester,
  Widget home,
  List<dynamic> overrides,
) async {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(path: '/coaching', builder: (_, _) => const SizedBox()),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [...overrides],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets(
    'A-1: an answer understood with the language model says so; rule-routed answers do not',
    (tester) async {
      final hybrid = Basis.fromJson({
        'sources': [
          {
            'kind': 'STATISTICS',
            'label': 'Ringkasan aktivitas 7 hari dari catatanmu',
          },
          {
            'kind': 'LANGUAGE_MODEL',
            'label':
                'Dipahami dengan bantuan model bahasa · aturan keselamatan tetap berlaku',
          },
        ],
        'memories': [],
      });
      final rules = Basis.fromJson({
        'sources': [
          {'kind': 'STATISTICS', 'label': 'x'},
        ],
        'memories': [],
      });
      expect(hybrid.languageModel, isTrue);
      expect(rules.languageModel, isFalse);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LanguageModelNote())),
      );
      expect(
        find.text(
          'Dipahami dengan bantuan model bahasa · aturan keselamatan tetap berlaku',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'A-4: temporary conditions show when they end; long-lived context shows when it is reviewed',
    (tester) async {
      _tall(tester);
      final overview = MemoryOverview.fromJson({
        'enabled': true,
        'consentGiven': true,
        'active': true,
        'items': [
          {
            'id': 'm1',
            'kind': 'HEALTH_EVENT',
            'kindLabel': 'Kondisi sementara',
            'content': 'Sedang berpuasa',
            'status': 'ACTIVE',
            'version': 1,
            'expiresAt': '2026-11-19T00:00:00Z',
          },
          {
            'id': 'm2',
            'kind': 'BARRIER',
            'kindLabel': 'Hambatan',
            'content': 'Sering lupa mencatat',
            'status': 'ACTIVE',
            'version': 1,
            'expiresAt': '2026-12-22T00:00:00Z',
          },
          {
            'id': 'm3',
            'kind': 'ACTIVITY_TIME',
            'kindLabel': 'Waktu aktivitas',
            'content': 'Lebih suka beraktivitas pagi hari',
            'status': 'ACTIVE',
            'version': 1,
            'expiresAt': null,
          },
        ],
      });
      await _pump(tester, const MemoryScreen(), [
        memoryOverviewProvider.overrideWith((ref) async => overview),
      ]);
      expect(find.text('Sedang berpuasa'), findsOneWidget);
      expect(find.text('Berakhir otomatis 19 Nov 2026'), findsOneWidget);
      expect(find.text('Diperiksa ulang 22 Des 2026'), findsOneWidget);
      expect(
        find.textContaining('Lebih suka beraktivitas pagi'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'A-5: the reflection shows what was learned last week and preselects remembered barriers',
    (tester) async {
      _tall(tester);
      final seen = <http.Request>[];
      final tokens = MemoryTokenStorage()..write('t');
      final api = ApiClient(
        tokens: tokens,
        baseUrl: 'http://test',
        client: MockClient((r) async {
          seen.add(r);
          if (r.url.path == '/api/me/coaching/checkins' && r.method == 'GET') {
            return _json({
              'consentRequired': false,
              'weekStart': '2026-11-08',
              'weekEnd': '2026-11-14',
              'done': null,
              'summary': {'recordedDays': 5, 'totalDays': 7},
              'goals': <dynamic>[],
              'actions': {
                'observed': 0,
                'confirmed': 0,
                'notObserved': 0,
                'planned': 0,
                'fromAssistant': 0,
                'items': <dynamic>[],
              },
              'positives': <dynamic>[],
              'adjustments': <dynamic>[],
              'learned': {
                'lines': [
                  '2 dari 3 hari rencana jalan kaki pagi terlaksana.',
                  'Rencana sore 2 kali kamu tolak, jadi aku tidak menawarkan sore dulu.',
                ],
              },
              'memoryBarriers': ['FORGOT'],
              'strategies': {
                'reviewStatus': 'DRAFT_NOT_CLINICALLY_REVIEWED',
                'byBarrier': {
                  'FORGOT': [
                    {
                      'key': 'FORGOT_PAIR',
                      'title': 'Catat langsung setelah makan',
                      'detail': 'x',
                    },
                  ],
                },
              },
              'streak': 0,
              'memoryAvailable': false,
              'preferredSlot': null,
            });
          }
          return _json({
            'checkin': {'id': 'c1', 'weekStart': '2026-11-08'},
            'recognition': ['Refleksi mingguan selesai'],
          }, 201);
        }),
      );
      await _pump(tester, const ReflectionScreen(), [
        coachingRepositoryProvider.overrideWithValue(
          CoachingRepository(api, isCurrentAccount: () => true),
        ),
      ]);
      expect(find.text('YANG KUPELAJARI MINGGU LALU'), findsOneWidget);
      expect(
        find.text(
          'Rencana sore 2 kali kamu tolak, jadi aku tidak menawarkan sore dulu.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();
      expect(find.text('Cara mengatasi: lupa'), findsOneWidget);
      await tester.tap(find.text('Simpan refleksi'));
      await tester.pumpAndSettle();
      final body =
          jsonDecode(seen.lastWhere((r) => r.method == 'POST').body)
              as Map<String, dynamic>;
      expect(body['hardest'], ['FORGOT']);
    },
  );
}
