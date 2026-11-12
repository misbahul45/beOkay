import 'dart:convert';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/features/coaching/application/coaching_controller.dart';
import 'package:app/features/coaching/data/coaching_repository.dart';
import 'package:app/features/coaching/presentation/coaching_screen.dart';
import 'package:app/features/coaching/presentation/reflection_screen.dart';
import 'package:app/features/interventions/application/intervention_controller.dart';
import 'package:app/features/interventions/data/intervention_repository.dart';
import 'package:app/features/interventions/presentation/intervention_card.dart';
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

const _today = '2026-11-12';

Map<String, dynamic> _action({
  required String status,
  List<Map<String, dynamic>> days = const [],
  String? slot,
  String? reminder,
}) => {
  'id': 'a1',
  'source': 'MEAL_LOG_GAP',
  'kind': 'MEAL_LOGGING',
  'title': 'Catat makan siang 3 hari ke depan',
  'rationale':
      'Hanya bila kamu memang makan siang; melewatkannya juga tidak apa-apa.',
  'evidence': {
    'summary':
        'Makan siang tercatat di 2 dari 9 hari yang punya catatan makan.',
    'window': '14 hari terakhir',
    'memories': <String>[],
  },
  'params': {'mealSlot': 'lunch'},
  'slot': slot,
  'startDate': _today,
  'endDate': '2026-11-14',
  'days': 3,
  'status': status,
  'phase': status == 'ACCEPTED' ? 'RUNNING' : status,
  'dayStates': days,
  'reminder': reminder == null
      ? null
      : {'id': 'r1', 'localTime': reminder, 'enabled': true},
};

List<Map<String, dynamic>> _days(String todayState) => [
  {'date': _today, 'state': todayState, 'today': true},
  {'date': '2026-11-13', 'state': 'PLANNED', 'today': false},
  {'date': '2026-11-14', 'state': 'PLANNED', 'today': false},
];

class _Backend {
  bool consent = true;
  bool accepted = false;
  String todayState = 'PLANNED';
  String? slot = 'MIDDAY';
  bool reflectionDone = false;
  final seen = <http.Request>[];

  Map<String, dynamic> overview() => {
    'consentRequired': !consent,
    'opportunities': consent && !accepted
        ? [_action(status: 'PROPOSED', slot: slot)]
        : <dynamic>[],
    'actions': consent && accepted
        ? [
            _action(
              status: 'ACCEPTED',
              days: _days(todayState),
              slot: slot,
              reminder: '07:00',
            ),
          ]
        : <dynamic>[],
    'reflection': consent
        ? {
            'weekStart': '2026-11-08',
            'weekEnd': '2026-11-14',
            'done': reflectionDone,
            'available': true,
          }
        : null,
    'preferences': {'slot': null},
  };

  Map<String, dynamic> reflection() => {
    'consentRequired': false,
    'weekStart': '2026-11-08',
    'weekEnd': '2026-11-14',
    'isCurrentWeek': true,
    'done': reflectionDone
        ? {
            'id': 'c1',
            'weekStart': '2026-11-08',
            'mood': 'HARD',
            'hardest': ['TIME'],
            'createdAt': '2026-11-12T05:00:00Z',
          }
        : null,
    'summary': {'recordedDays': 5, 'totalDays': 7},
    'goals': [
      {
        'id': 'g1',
        'title': 'Aktif 150 menit',
        'goalType': 'activity_minutes',
        'period': 'weekly',
        'target': 150,
        'value': 45,
        'ratio': 0.3,
      },
    ],
    'actions': {
      'observed': 2,
      'confirmed': 1,
      'notObserved': 1,
      'planned': 0,
      'fromAssistant': 0,
      'items': [
        {'id': 'a1', 'title': 'Jalan kaki 10 menit, 3 hari'},
      ],
    },
    'positives': [
      'Makan tercatat di 5 dari 7 hari',
      '45 menit aktivitas tercatat di 3 hari',
    ],
    'adjustments': [
      {
        'goalId': 'g1',
        'title': 'Aktif 150 menit',
        'goalType': 'activity_minutes',
        'fromTarget': 150,
        'toTarget': 80,
        'expectedVersion': 1,
        'basis': 'Dari catatanmu: 45 menit minggu ini.',
      },
    ],
    'streak': reflectionDone ? 1 : 0,
    'history': <dynamic>[],
    'memoryAvailable': true,
    'preferredSlot': null,
    'nudge': !reflectionDone,
  };

  http.Response handle(http.Request r) {
    seen.add(r);
    final path = r.url.path;
    final body = r.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(r.body) as Map<String, dynamic>;
    if (path == '/api/me/coaching') return _json(overview());
    if (path.endsWith('/decision')) {
      accepted = body['decision'] == 'ACCEPT';
      slot = body['slot'] as String? ?? slot;
      return _json(
        _action(
          status: accepted ? 'ACCEPTED' : 'DECLINED',
          days: _days(todayState),
        ),
      );
    }
    if (path.endsWith('/confirm')) {
      todayState = 'USER_CONFIRMED';
      return _json(_action(status: 'ACCEPTED', days: _days(todayState)));
    }
    if (path.endsWith('/feedback')) {
      if (body['kind'] == 'PREFER_DIFFERENT_TIME') {
        slot = body['slot'] as String;
      }
      return _json(
        _action(status: accepted ? 'ACCEPTED' : 'PROPOSED', slot: slot),
      );
    }
    if (path == '/api/me/coaching/checkins' && r.method == 'GET') {
      return _json(reflection());
    }
    if (path == '/api/me/coaching/checkins') {
      reflectionDone = true;
      return _json({
        'checkin': {'id': 'c1', 'weekStart': '2026-11-08'},
        'recognition': [
          'Refleksi mingguan selesai',
          '2 rencana kecil terlaksana',
        ],
        'replayed': false,
      }, 201);
    }
    return _json({}, 404);
  }

  Map<String, dynamic> lastBody(String suffix) =>
      jsonDecode(
            seen
                .lastWhere(
                  (r) => r.method == 'POST' && r.url.path.endsWith(suffix),
                )
                .body,
          )
          as Map<String, dynamic>;
}

Future<Widget> _app(_Backend b, {String start = '/'}) async {
  final tokens = MemoryTokenStorage();
  await tokens.write('t');
  final api = ApiClient(
    tokens: tokens,
    baseUrl: 'http://test',
    client: MockClient((r) async => b.handle(r)),
  );
  final router = GoRouter(
    initialLocation: start,
    routes: [
      GoRoute(path: '/', builder: (_, _) => const CoachingScreen()),
      GoRoute(path: '/coaching', builder: (_, _) => const CoachingScreen()),
      GoRoute(
        path: '/coaching/reflection',
        builder: (_, _) => const ReflectionScreen(),
      ),
      GoRoute(
        path: '/settings/consent',
        builder: (_, _) => const Scaffold(body: Text('Halaman persetujuan')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      coachingRepositoryProvider.overrideWithValue(
        CoachingRepository(api, isCurrentAccount: () => true),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets(
    'An opportunity shows its evidence; accepting picks a time and an optional reminder; the plan shows per-day states and can be confirmed',
    (tester) async {
      _tall(tester);
      final b = _Backend();
      await tester.pumpWidget(await _app(b));
      await tester.pumpAndSettle();
      expect(find.text('Catat makan siang 3 hari ke depan'), findsOneWidget);
      expect(
        find.text(
          'Makan siang tercatat di 2 dari 9 hari yang punya catatan makan. (14 hari terakhir)',
        ),
        findsOneWidget,
      );
      expect(find.text('Refleksi mingguan siap'), findsOneWidget);

      await tester.tap(find.text('Coba rencana ini'));
      await tester.pumpAndSettle();
      expect(find.text('Kapan enaknya?'), findsOneWidget);
      await tester.tap(find.text('Pagi'));
      await tester.tap(find.text('Ingatkan aku'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mulai rencana'));
      await tester.pumpAndSettle();
      final decision = b.lastBody('/decision');
      expect(decision['decision'], 'ACCEPT');
      expect(decision['slot'], 'MORNING');
      expect(decision['reminder'], <String, dynamic>{});
      expect(decision['operationId'], isA<String>());

      expect(find.text('RENCANA BERJALAN'), findsOneWidget);
      expect(find.text('Pagi · Pengingat 07.00 aktif'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Kamis, hari ini: direncanakan'),
        findsOneWidget,
      );
      await tester.tap(find.text('Sudah kulakukan hari ini'));
      await tester.pumpAndSettle();
      expect(b.lastBody('/confirm')['date'], _today);
      expect(
        find.bySemanticsLabel('Kamis, hari ini: kamu konfirmasi'),
        findsOneWidget,
      );
      expect(find.text('Sudah kulakukan hari ini'), findsNothing);
    },
  );

  testWidgets(
    'Feedback: every option is available; a different time asks for the time and sends it; not now and stop send their kind',
    (tester) async {
      _tall(tester);
      final b = _Backend();
      await tester.pumpWidget(await _app(b));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Umpan balik'));
      await tester.pumpAndSettle();
      for (final label in [
        'Membantu',
        'Kurang membantu',
        'Sudah kulakukan',
        'Bukan sekarang',
        'Terlalu sering',
        'Waktu lain',
        'Saran lain',
        'Jangan sarankan ini lagi',
      ]) {
        expect(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
      }
      await tester.tap(find.text('Waktu lain'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Malam (19.00)'));
      await tester.pumpAndSettle();
      expect(
        b.lastBody('/feedback'),
        containsPair('kind', 'PREFER_DIFFERENT_TIME'),
      );
      expect(b.lastBody('/feedback'), containsPair('slot', 'EVENING'));
      expect(find.text('Waktu diubah ke malam.'), findsOneWidget);

      await tester.tap(find.text('Bukan sekarang'));
      await tester.pumpAndSettle();
      expect(b.lastBody('/feedback')['kind'], 'NOT_NOW');

      await tester.tap(find.byTooltip('Umpan balik'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jangan sarankan ini lagi'));
      await tester.pumpAndSettle();
      expect(b.lastBody('/feedback')['kind'], 'STOP_THIS_TYPE');
    },
  );

  testWidgets(
    'Without consent nothing is suggested and the consent page is offered',
    (tester) async {
      _tall(tester);
      final b = _Backend()..consent = false;
      await tester.pumpWidget(await _app(b));
      await tester.pumpAndSettle();
      expect(find.text('Persetujuan diperlukan'), findsOneWidget);
      expect(find.text('Coba rencana ini'), findsNothing);
      await tester.tap(find.text('Kelola persetujuan'));
      await tester.pumpAndSettle();
      expect(find.text('Halaman persetujuan'), findsOneWidget);
    },
  );

  testWidgets(
    'Weekly reflection: summary from records, conversational questions, adjustments only when switched on, remembered time, recognition',
    (tester) async {
      _tall(tester);
      final b = _Backend();
      await tester.pumpWidget(await _app(b, start: '/coaching/reflection'));
      await tester.pumpAndSettle();
      expect(find.text('Ada yang berjalan baik minggu ini'), findsOneWidget);
      expect(find.text('Makan tercatat di 5 dari 7 hari'), findsOneWidget);
      expect(
        find.text('2 tercatat · 1 kamu konfirmasi · 1 belum terlihat'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Belum terlihat bukan berarti gagal — mungkin hanya belum dicatat.',
        ),
        findsOneWidget,
      );
      expect(find.text('Data tercatat di 5 dari 7 hari'), findsOneWidget);
      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();

      expect(find.text('Bagaimana minggu ini menurutmu?'), findsOneWidget);
      await tester.tap(find.text('Berat'));
      await tester.tap(find.text('Waktu'));
      await tester.enterText(find.byType(TextField), 'Lembur');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();

      expect(find.text('Ringankan target: 150 → 80 menit'), findsOneWidget);
      expect(find.text('Ingat waktu ini untuk saran berikutnya'), findsNothing);
      await tester.tap(find.text('Pagi'));
      await tester.pumpAndSettle();
      expect(
        find.text('Ingat waktu ini untuk saran berikutnya'),
        findsOneWidget,
      );
      await tester.tap(find.text('Simpan refleksi'));
      await tester.pumpAndSettle();
      var body = b.lastBody('/checkins');
      expect(body['weekStart'], '2026-11-08');
      expect(body['mood'], 'HARD');
      expect(body['hardest'], ['TIME']);
      expect(body['note'], 'Lembur');
      expect(body['adjustments'], isEmpty);
      expect(body['preferredSlot'], 'MORNING');
      expect(body['rememberSlot'], true);
      expect(find.text('Refleksi mingguan selesai'), findsOneWidget);
      expect(find.text('2 rencana kecil terlaksana'), findsOneWidget);

      final c = _Backend();
      await tester.pumpWidget(await _app(c, start: '/coaching/reflection'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjut'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aktif 150 menit').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan refleksi'));
      await tester.pumpAndSettle();
      body = c.lastBody('/checkins');
      expect(body['adjustments'], [
        {'goalId': 'g1', 'toTarget': 80},
      ]);
      expect(body.containsKey('preferredSlot'), isFalse);
      expect(body.containsKey('mood'), isFalse);
    },
  );

  testWidgets('A completed reflection is shown read-only', (tester) async {
    _tall(tester);
    final b = _Backend()..reflectionDone = true;
    await tester.pumpWidget(await _app(b, start: '/coaching/reflection'));
    await tester.pumpAndSettle();
    expect(find.text('Refleksi ini sudah tersimpan'), findsOneWidget);
    expect(find.text('Lanjut'), findsNothing);
  });

  testWidgets(
    'Home card: a clarification question offers keep or stop; a plan card opens the plan',
    (tester) async {
      final sent = <Map<String, dynamic>>[];
      final tokens = MemoryTokenStorage();
      await tokens.write('t');
      final api = ApiClient(
        tokens: tokens,
        baseUrl: 'http://test',
        client: MockClient((r) async {
          sent.add({
            'path': r.url.path,
            ...jsonDecode(r.body) as Map<String, dynamic>,
          });
          return _json({});
        }),
      );
      Intervention card(String option, String action) => Intervention.fromJson({
        'id': 'i1',
        'trigger': 'COACHING_ACTION_DUE',
        'option': option,
        'content': {
          'title': option == 'CLARIFICATION_QUESTION'
              ? 'Masih mau diingatkan?'
              : 'Rencana hari ini',
          'body': 'x',
          'action': action,
        },
      });
      Future<void> pump(Intervention i) async {
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: InterventionCard()),
            ),
            GoRoute(
              path: '/coaching',
              builder: (_, _) => const Scaffold(body: Text('Halaman rencana')),
            ),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              interventionRepositoryProvider.overrideWithValue(
                InterventionRepository(api, isCurrentAccount: () => true),
              ),
              openInterventionsProvider.overrideWith((_) async => [i]),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pump(card('CLARIFICATION_QUESTION', 'ASK'));
      expect(find.text('Buka'), findsNothing);
      await tester.tap(find.text('Ya, tetap'));
      await tester.pumpAndSettle();
      expect(sent.last, containsPair('kind', 'USEFUL'));
      await pump(card('CLARIFICATION_QUESTION', 'ASK'));
      await tester.tap(find.text('Tidak usah'));
      await tester.pumpAndSettle();
      expect(sent.last, containsPair('kind', 'STOP_THIS_TYPE'));

      await pump(card('ACTION_REMINDER_CARD', 'OPEN_COACHING'));
      await tester.tap(find.text('Buka'));
      await tester.pumpAndSettle();
      expect(sent.last, containsPair('kind', 'OPENED'));
      expect(find.text('Halaman rencana'), findsOneWidget);
    },
  );
}
