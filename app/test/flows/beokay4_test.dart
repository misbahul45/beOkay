import 'dart:convert';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/offline/offline_queue.dart';
import 'package:app/core/offline/sync_controller.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/core/widgets/beokay_spark.dart';
import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/auth/data/session_user.dart';
import 'package:app/features/coach/data/conversation_models.dart';
import 'package:app/features/coach/presentation/chat_parts.dart';
import 'package:app/features/community/presentation/challenge_screen.dart';
import 'package:app/features/devices/presentation/devices_screen.dart';
import 'package:app/features/health_profile/presentation/health_profile_screen.dart';
import 'package:app/features/journey/presentation/journey_screen.dart';
import 'package:app/features/memory/presentation/memory_screen.dart';
import 'package:app/features/next_action/presentation/next_action_section.dart';
import 'package:app/features/notifications/application/realtime_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class _QuietRealtime extends RealtimeController {
  @override
  RealtimeState build() => const RealtimeState();
  @override
  void subscribe(String topic) {}
  @override
  void unsubscribe(String topic) {}
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
  List<http.Request> sent(String path, String method) => [
    for (final r in seen)
      if (r.url.path == path && r.method == method) r,
  ];
}

Future<void> _pump(WidgetTester tester, _Api api, Widget home) async {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: home),
      ),
      for (final p in [
        '/coach',
        '/coaching',
        '/settings/memory',
        '/log',
        '/profile/health',
        '/reminders',
        '/settings/consent',
        '/activities/weekly',
        '/coaching/reflection',
      ])
        GoRoute(
          path: p,
          builder: (_, _) => Scaffold(body: Text('route $p')),
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
        keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
        realtimeProvider.overrideWith(_QuietRealtime.new),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, dynamic> _nextAction(
  String kind,
  String spark, {
  String? energy,
  String journey = 'PREVENTION',
}) => {
  'version': 'next-action-v1',
  'flow': [
    'TODAY',
    'NEXT_ACTION',
    'CONFIRM',
    'PROGRESS',
    'REFLECTION',
    'INSIGHTS',
    'CHALLENGES',
  ],
  'journey': journey,
  'today': '2026-11-13',
  'energy': energy,
  'action': {
    'kind': kind,
    'step': kind == 'CONFIRM_RECOMMENDATION' ? 'CONFIRM' : 'TODAY',
    'spark': spark,
    'title': kind == 'SAFETY_FOLLOW_UP'
        ? 'Utamakan keselamatanmu'
        : 'Ada pilihan menunggu persetujuanmu',
    'body': 'Tidak ada yang disimpan sebelum kamu memilih.',
    'target': kind == 'SAFETY_FOLLOW_UP' ? 'COACH' : 'COACH',
    'ref': 'r1',
    'source': 'agent_recommendation',
  },
  'progress': {
    'scoreVersion': 'score-v2',
    'week': {
      'activeDays': 3,
      'deviceDays': 2,
      'effort': 2.6,
      'selfProgressBonus': 0,
      'total': 2.6,
    },
    'personalBest': {'best7DayActive': 5, 'longestStreak': 3},
    'returnAfterBreak': {'returned': false, 'gapDays': null},
  },
};

Map<String, dynamic> _memory(
  String id,
  String content, {
  String status = 'ACTIVE',
  String conflict = 'NONE',
  bool paused = false,
  String sourceType = 'CONVERSATION',
  String memoryType = 'ROUTINE',
}) => {
  'id': id,
  'category': 'PREFERENCE',
  'kind': 'ACTIVITY_TIME',
  'kindLabel': 'Waktu aktivitas',
  'content': content,
  'status': status,
  'sourceType': sourceType,
  'version': 1,
  'confirmedAt': status == 'ACTIVE' ? '2026-11-12T01:00:00.000Z' : null,
  'expiresAt': null,
  'updatedAt': '2026-11-12T01:00:00.000Z',
  'memoryType': memoryType,
  'conflictState': conflict,
  'paused': paused,
  'pauseReason': paused ? 'CONSENT_WITHDRAWN' : null,
};

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets(
    '4.0-A: pernyataan risiko muncul bila belum terdiagnosis dan dikirim ke server',
    (tester) async {
      final api = _Api();
      api.extra = (r) => switch ((r.url.path, r.method)) {
        ('/api/me/health-profile', 'GET') => _json({
          'exists': true,
          'diagnosisStatus': 'not_diagnosed',
          'diabetesType': null,
          'diagnosedYear': null,
          'treatmentContext': [],
          'riskStatement': null,
          'journey': {'value': 'WELLNESS', 'label': 'Gaya hidup sehat'},
        }),
        ('/api/me/health-profile', 'PUT') => _json({
          'exists': true,
          'diagnosisStatus': 'not_diagnosed',
          'diabetesType': null,
          'diagnosedYear': null,
          'treatmentContext': [],
          'riskStatement': 'prediabetes_told',
          'journey': {'value': 'PREVENTION', 'label': 'Pencegahan'},
        }),
        _ => null,
      };
      await _pump(tester, api, const HealthProfileScreen(onboarding: false));
      expect(
        find.text('Apakah tenaga kesehatan pernah bilang…'),
        findsOneWidget,
      );
      await tester.tap(find.text('Saya prediabetes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      final put = api.sent('/api/me/health-profile', 'PUT').single;
      expect(
        jsonDecode(put.body),
        containsPair('riskStatement', 'prediabetes_told'),
      );
    },
  );

  testWidgets('4.0-A: pertanyaan risiko disembunyikan untuk diagnosis T2DM', (
    tester,
  ) async {
    final api = _Api();
    api.extra = (r) => r.url.path == '/api/me/health-profile'
        ? _json({
            'exists': true,
            'diagnosisStatus': 'diagnosed',
            'diabetesType': 'type_2',
            'diagnosedYear': 2020,
            'treatmentContext': ['lifestyle'],
            'riskStatement': null,
            'journey': {
              'value': 'T2DM_SUPPORT',
              'label': 'Dukungan diabetes tipe 2',
            },
          })
        : null;
    await _pump(tester, api, const HealthProfileScreen(onboarding: false));
    expect(find.text('Apakah tenaga kesehatan pernah bilang…'), findsNothing);
  });

  testWidgets('4.0-B: Jalurmu menampilkan jalur, sumber, dan kemampuan', (
    tester,
  ) async {
    final api = _Api();
    api.extra = (r) => r.url.path == '/api/me/journey'
        ? _json({
            'journey': 'PREVENTION',
            'label': 'Pencegahan',
            'description':
                'Kamu pernah diberi tahu tenaga kesehatan bahwa kamu berisiko.',
            'source': 'user_statement',
            'assumed': false,
            'setAt': '2026-11-13T00:00:00.000Z',
            'capabilities': {
              'coaching': true,
              'assistant': true,
              'community': true,
              'glucoseFeaturesVisible': false,
              'medicationFeaturesVisible': false,
              'screeningReminder': true,
            },
          })
        : null;
    await _pump(tester, api, const JourneyScreen());
    expect(find.text('Pencegahan'), findsOneWidget);
    expect(find.text('dari pernyataanmu'), findsOneWidget);
    expect(
      find.text('Bacaan pencegahan dan pemeriksaan rutin'),
      findsOneWidget,
    );
    expect(
      find.text('Glukosa dan obat (bisa dinyalakan di Catat)'),
      findsOneWidget,
    );
  });

  testWidgets(
    '4.0-C: langkah berikutnya, alur, progres score-v2, dan check-in energi',
    (tester) async {
      final api = _Api();
      api.extra = (r) => switch ((r.url.path, r.method)) {
        ('/api/me/today/next-action', 'GET') => _json(
          _nextAction(
            'CONFIRM_RECOMMENDATION',
            'AWAITING_CONFIRMATION',
            energy: 'OK',
          ),
        ),
        ('/api/me/checkins/energy', 'PUT') => _json({
          'localDate': '2026-11-13',
          'checkin': {'energy': 'LOW', 'version': 2},
        }),
        _ => null,
      };
      await _pump(
        tester,
        api,
        const SingleChildScrollView(child: NextActionSection()),
      );
      expect(find.text('LANGKAH BERIKUTNYA · KONFIRMASI'), findsOneWidget);
      expect(find.text('Ada pilihan menunggu persetujuanmu'), findsOneWidget);
      expect(
        tester.widget<BeOkaySpark>(find.byType(BeOkaySpark)).state,
        SparkState.awaitingConfirmation,
      );
      expect(find.text('Konfirmasi'), findsOneWidget);
      expect(find.text('PROGRES MINGGU INI'), findsOneWidget);
      expect(find.text('skor minggu ini'), findsOneWidget);
      expect(find.textContaining('Rekor 7 hari:'), findsOneWidget);
      await tester.tap(find.text('Lelah'));
      await tester.pumpAndSettle();
      expect(
        jsonDecode(api.sent('/api/me/checkins/energy', 'PUT').single.body),
        {'energy': 'LOW'},
      );
      await tester.tap(find.text('Lihat pilihan'));
      await tester.pumpAndSettle();
      expect(find.text('route /coach'), findsOneWidget);
    },
  );

  testWidgets(
    '4.0-C2: chip alur membuka bagiannya, skor minggu ini tampil, dan layar lebar memakai dua kolom',
    (tester) async {
      final api = _Api();
      api.extra = (r) => r.url.path == '/api/me/today/next-action'
          ? _json(
              _nextAction('CONFIRM_RECOMMENDATION', 'AWAITING_CONFIRMATION'),
            )
          : null;
      await _pump(
        tester,
        api,
        const SingleChildScrollView(child: NextActionSection()),
      );
      expect(find.text('2,6'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('PROGRES MINGGU INI')).dy,
        lessThan(tester.getTopLeft(find.text('Lihat pilihan')).dy),
      );
      expect(
        tester.getTopLeft(find.text('PROGRES MINGGU INI')).dx,
        greaterThan(tester.getTopLeft(find.text('Lihat pilihan')).dx),
      );
      await tester.ensureVisible(find.text('Progres'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Progres'));
      await tester.pumpAndSettle();
      expect(find.text('route /activities/weekly'), findsOneWidget);
    },
  );

  testWidgets(
    '4.0-C3: di ponsel kartu bertumpuk satu kolom dan chip Konfirmasi membuka target aksi',
    (tester) async {
      final api = _Api();
      api.extra = (r) => r.url.path == '/api/me/today/next-action'
          ? _json(
              _nextAction('CONFIRM_RECOMMENDATION', 'AWAITING_CONFIRMATION'),
            )
          : null;
      await _pump(
        tester,
        api,
        const SingleChildScrollView(child: NextActionSection()),
      );
      tester.view.physicalSize = const Size(390, 3200);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('PROGRES MINGGU INI')).dy,
        greaterThan(tester.getTopLeft(find.text('Lihat pilihan')).dy),
      );
      await tester.ensureVisible(find.text('Konfirmasi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Konfirmasi'));
      await tester.pumpAndSettle();
      expect(find.text('route /coach'), findsOneWidget);
    },
  );

  testWidgets(
    '4.0-D: keselamatan menampilkan SAFETY_WARNING dan menyembunyikan progres serta energi',
    (tester) async {
      final api = _Api();
      api.extra = (r) => r.url.path == '/api/me/today/next-action'
          ? _json(_nextAction('SAFETY_FOLLOW_UP', 'SAFETY_WARNING'))
          : null;
      await _pump(
        tester,
        api,
        const SingleChildScrollView(child: NextActionSection()),
      );
      expect(find.text('UTAMAKAN KESELAMATAN'), findsOneWidget);
      expect(
        tester.widget<BeOkaySpark>(find.byType(BeOkaySpark)).state,
        SparkState.safetyWarning,
      );
      expect(find.text('PROGRES MINGGU INI'), findsNothing);
      expect(find.text('Lelah'), findsNothing);
    },
  );

  testWidgets(
    '4.0-E: memori menampilkan konflik, usulan dari catatan, dan yang dijeda; aksi memanggil API',
    (tester) async {
      final api = _Api();
      api.extra = (r) => switch ((r.url.path, r.method)) {
        ('/api/me/memories', 'GET') => _json({
          'enabled': true,
          'consentGiven': true,
          'active': true,
          'items': [
            _memory(
              'm1',
              'Lebih suka beraktivitas pagi hari',
              conflict: 'CONFLICTING',
            ),
          ],
          'paused': [_memory('m3', 'Sedang flu minggu ini', paused: true)],
          'conflicts': [
            _memory(
              'm2',
              'Lebih suka beraktivitas sore hari',
              status: 'PROPOSED',
              conflict: 'CONFLICTING',
            ),
          ],
          'proposals': [
            _memory(
              'm4',
              'Lebih suka beraktivitas malam hari',
              status: 'PROPOSED',
              sourceType: 'DERIVED',
              memoryType: 'DERIVED',
            ),
          ],
        }),
        ('/api/me/memories/m3/resume', 'POST') => _json(
          _memory('m3', 'Sedang flu minggu ini'),
        ),
        ('/api/me/memories/m2/confirm', 'POST') => _json(_memory('m2', 'x')),
        _ => null,
      };
      await _pump(tester, api, const MemoryScreen());
      expect(find.text('DUA INGATAN BERTENTANGAN'), findsOneWidget);
      expect(find.text('Mana yang benar sekarang?'), findsOneWidget);
      expect(find.text('TERSIMPAN'), findsOneWidget);
      expect(find.text('BARU'), findsOneWidget);
      expect(find.text('Lebih suka beraktivitas sore hari'), findsOneWidget);
      expect(find.text('USULAN DARI CATATANMU'), findsOneWidget);
      expect(find.text('DIJEDA · TIDAK DIPAKAI'), findsOneWidget);
      expect(
        find.text('Dijeda karena persetujuan saran personal dicabut'),
        findsOneWidget,
      );
      await tester.tap(find.text('Lanjutkan'));
      await tester.pumpAndSettle();
      expect(api.sent('/api/me/memories/m3/resume', 'POST'), hasLength(1));
      await tester.tap(find.text('Pakai yang baru'));
      await tester.pumpAndSettle();
      expect(api.sent('/api/me/memories/m2/confirm', 'POST'), hasLength(1));
    },
  );

  testWidgets(
    '4.0-F: status perangkat menampilkan cakupan, asal data, dan sakelar data untuk saran',
    (tester) async {
      final api = _Api();
      api.extra = (r) => switch ((r.url.path, r.method)) {
        ('/api/me/devices/status', 'GET') => _json({
          'version': 'device-quality-v1',
          'usedForCoaching': true,
          'lastSyncAt': {
            'steps': DateTime.now()
                .subtract(const Duration(hours: 2))
                .toUtc()
                .toIso8601String(),
            'sleep': null,
            'workouts': null,
          },
          'origins': [
            'com.google.android.apps.fitness',
            'com.samsung.android.wear.shealth',
          ],
          'signals': [
            {
              'signal': 'steps',
              'days': 14,
              'observedDays': 11,
              'coverage': 0.79,
              'statusCounts': {'OK': 11},
              'reliable': true,
            },
            {
              'signal': 'sleep',
              'days': 14,
              'observedDays': 7,
              'coverage': 0.5,
              'statusCounts': {'OK': 6, 'CONFLICT': 1},
              'reliable': false,
            },
          ],
          'days': {},
          'notice':
              'Hari tanpa data perangkat tidak pernah dianggap tidak aktif. Angka dari perangkat adalah perkiraan.',
        }),
        ('/api/me/consents/withdraw', 'POST') => _json({
          'policyVersion': '1.1',
          'purposes': [],
          'history': [],
        }),
        _ => null,
      };
      await _pump(tester, api, const DevicesScreen());
      expect(find.text('14 HARI TERAKHIR'), findsOneWidget);
      expect(find.text('79%'), findsOneWidget);
      expect(find.textContaining('1 hari dari dua perangkat'), findsOneWidget);
      expect(
        find.text('Google Fit · Samsung Health (jam tangan)'),
        findsOneWidget,
      );
      expect(
        find.textContaining('tidak pernah dianggap tidak aktif'),
        findsOneWidget,
      );
      await tester.tap(find.text('Pakai data perangkat untuk saran'));
      await tester.pumpAndSettle();
      expect(
        jsonDecode(api.sent('/api/me/consents/withdraw', 'POST').single.body),
        {
          'purposes': ['device_data_coaching'],
        },
      );
    },
  );

  test('4.0-G: part evidence dan strategy dibaca dari JSON', () {
    final e = ChatPart.fromJson({
      'type': 'evidence',
      'certainty': 'insufficient',
      'items': [
        {
          'title': 'Mencegah diabetes',
          'source': 'ADA 2026',
          'reviewStatus': 'DRAFT',
          'lane': 'A_PUBLIC_HEALTH',
        },
      ],
    });
    expect(e, isA<EvidencePart>());
    expect((e as EvidencePart).certaintyLabel, 'Belum ditinjau');
    final s = ChatPart.fromJson({
      'type': 'strategy',
      'barrier': 'FORGOT',
      'key': 'FORGOT_REMINDER',
      'title': 'Pasang satu pengingat',
      'detail':
          'Pasang satu pengingat. Satu pengingat di jam yang paling sering terlewat. Hambatan: Lupa.',
      'reviewStatus': 'DRAFT',
    });
    expect((s as StrategyPart).detail.contains('Hambatan:'), isFalse);
    expect(s.barrierLabel, 'lupa');
  });

  testWidgets('4.0-G: kartu strategi dan chip kepastian tampil', (
    tester,
  ) async {
    final api = _Api();
    await _pump(
      tester,
      api,
      const Column(
        children: [
          EvidenceChips(
            part: EvidencePart(
              certainty: 'verified',
              items: [(title: 'A', source: 'ADA 2026', reviewed: true)],
            ),
          ),
          StrategyCard(
            part: StrategyPart(
              barrier: 'FORGOT',
              key: 'FORGOT_REMINDER',
              title: 'Pasang satu pengingat',
              detail: 'Satu pengingat di jam yang paling sering terlewat.',
            ),
          ),
        ],
      ),
    );
    expect(find.text('Kepastian: terverifikasi'), findsOneWidget);
    expect(find.text('Sumber: ADA 2026'), findsOneWidget);
    expect(find.text('STRATEGI UNTUK HAMBATAN: LUPA'), findsOneWidget);
    await tester.tap(find.text('Atur pengingat'));
    await tester.pumpAndSettle();
    expect(find.text('route /reminders'), findsOneWidget);
  });

  for (final (participants, visible) in [(6, true), (4, false)]) {
    testWidgets('4.0-I: misi tim $participants anggota → tampil=$visible', (
      tester,
    ) async {
      final api = _Api();
      api.extra = (r) => switch (r.url.path) {
        '/api/me/challenges/ch1' => _json({
          'id': 'ch1',
          'communityId': 'c1',
          'title': 'Misi tim: 7 hari bergerak bersama',
          'description': 'Setiap hari aktif anggota menambah progres tim.',
          'kind': 'TEAM_ACTIVE_DAYS',
          'teamTargetDays': 20,
          'startsOn': '2026-11-09',
          'endsOn': '2026-11-15',
          'targetDays': 3,
          'status': 'OPEN',
          'statusLabel': 'Berjalan · sisa 3 hari',
          'daysLeft': 3,
          'participating': true,
          'leaderboardVisible': false,
          'participantsLabel': '5 peserta atau lebih',
          'community': {
            'id': 'c1',
            'name': 'Komunitas uji',
            'region': 'Jawa Timur',
          },
          'alias': 'jalan.pagi',
          'rules': [
            'Hari aktif = satu sesi aktivitas tercatat minimal 10 menit.',
          ],
          'progress': {
            'score': 20.0,
            'activeDays': 2,
            'activityDays': 2,
            'checkinDays': 0,
          },
          'myResult': null,
          'canJoin': false,
          'canCheckin': true,
          'checkedInToday': false,
        }),
        '/api/me/challenges/ch1/team' => _json({
          'challengeId': 'ch1',
          'kind': 'TEAM_ACTIVE_DAYS',
          'teamTargetDays': 20,
          'participants': participants,
          'minParticipants': 5,
          'visible': visible,
          'teamActiveDays': visible ? 14 : null,
          'contributors': visible ? 6 : null,
          'note': '',
        }),
        '/api/me/challenges/ch1/leaderboard' => _json({
          'suppressed': true,
          'reason': 'x',
          'items': [],
        }),
        _ => null,
      };
      await _pump(tester, api, const ChallengeDetailScreen(challengeId: 'ch1'));
      if (visible) {
        expect(find.text('PROGRES TIM'), findsOneWidget);
        expect(find.text('14'), findsOneWidget);
        expect(find.text('anggota berkontribusi'), findsOneWidget);
      } else {
        expect(find.text('PROGRES TIM'), findsNothing);
        expect(find.textContaining('Sekarang: 4 anggota'), findsOneWidget);
      }
      expect(find.text('Kontribusimu'.toUpperCase()), findsOneWidget);
    });
  }

  test('Spark: pemetaan keadaan dari server', () {
    expect(
      sparkStateFromWire('AWAITING_CONFIRMATION'),
      SparkState.awaitingConfirmation,
    );
    expect(sparkStateFromWire('SAFETY_WARNING'), SparkState.safetyWarning);
    expect(sparkStateFromWire('CELEBRATING'), SparkState.celebrating);
    expect(sparkStateFromWire(null), SparkState.neutral);
    expect(sparkStateFromWire('APA_SAJA'), SparkState.neutral);
  });
}
