import 'dart:convert';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/features/community/application/community_controller.dart';
import 'package:app/features/community/data/community_repository.dart';
import 'package:app/features/community/presentation/challenge_screen.dart';
import 'package:app/features/community/presentation/community_privacy_screen.dart';
import 'package:app/features/community/presentation/community_screen.dart';
import 'package:app/features/notifications/application/realtime_controller.dart';
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

class _QuietRealtime extends RealtimeController {
  final topics = <String>[];
  @override
  RealtimeState build() => const RealtimeState();
  @override
  void subscribe(String topic) => topics.add(topic);
  @override
  void unsubscribe(String topic) => topics.remove(topic);
}

Future<(CommunityRepository, List<http.Request>)> _repo(
  http.Response Function(http.Request) h,
) async {
  final tokens = MemoryTokenStorage();
  await tokens.write('t');
  final seen = <http.Request>[];
  return (
    CommunityRepository(
      ApiClient(
        tokens: tokens,
        baseUrl: 'http://test',
        client: MockClient((r) async {
          seen.add(r);
          return h(r);
        }),
      ),
      isCurrentAccount: () => true,
    ),
    seen,
  );
}

Widget _app(CommunityRepository repo, Widget home) => ProviderScope(
  key: UniqueKey(),
  overrides: [
    communityRepositoryProvider.overrideWithValue(repo),
    realtimeProvider.overrideWith(_QuietRealtime.new),
  ],
  child: MaterialApp.router(
    routerConfig: GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => home),
        GoRoute(
          path: '/settings/consent',
          builder: (_, _) => const Scaffold(body: Text('Halaman persetujuan')),
        ),
        GoRoute(
          path: '/community/privacy',
          builder: (_, _) => const Scaffold(body: Text('Halaman privasi')),
        ),
      ],
    ),
  ),
);

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 3600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Map<String, dynamic> _summary({
  String status = 'OPEN',
  bool participating = false,
  Map<String, dynamic>? progress,
}) => {
  'id': 'ch1',
  'communityId': 'c1',
  'title': '3 hari aktif minggu ini',
  'description': 'Hari aktif = satu sesi tercatat atau check-in.',
  'startsOn': '2026-11-09',
  'endsOn': '2026-11-15',
  'targetDays': 3,
  'status': status,
  'statusLabel': status == 'CLOSED' ? 'Selesai' : 'Berjalan · sisa 5 hari',
  'daysLeft': status == 'OPEN' ? 5 : null,
  'participating': participating,
  'leaderboardVisible': false,
  'participantsLabel': 'kurang dari 5 peserta',
  'progress': ?progress,
};

Map<String, dynamic> _detail({
  String status = 'OPEN',
  bool participating = false,
  bool visible = false,
  Map<String, dynamic>? result,
}) => {
  ..._summary(status: status, participating: participating),
  'leaderboardVisible': visible,
  'community': {
    'id': 'c1',
    'name': 'Hidup Seimbang Jawa Timur',
    'region': 'Jawa Timur',
  },
  'alias': 'jalan.pagi',
  'rules': [
    'Hari aktif = satu sesi aktivitas tercatat minimal 10 menit atau check-in kebiasaan.',
    'Tidak ada poin untuk intensitas, berat badan, gula darah, atau nilai kesehatan lain.',
  ],
  'progress': participating
      ? {'score': 37.0, 'activeDays': 1, 'activityDays': 1, 'checkinDays': 0}
      : null,
  'myResult': result,
  'canJoin': !participating && status != 'CLOSED',
  'canCheckin': participating && status == 'OPEN',
};

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets(
    'Hub: running challenges with progress, private recognitions, memberships; discovery previews challenges and joining asks for an alias',
    (tester) async {
      String? joinedAlias;
      final (repo, seen) = await _repo((r) {
        switch (r.url.path) {
          case '/api/me/community/overview':
            return _json({
              'consentRequired': false,
              'memberships': [
                {
                  'communityId': 'c9',
                  'name': 'Hidup Seimbang Bali',
                  'region': 'Bali',
                  'alias': 'x90',
                  'joinedAt': '2026-11-01T00:00:00Z',
                  'openChallenges': 2,
                },
              ],
              'challenges': [
                _summary(
                  participating: true,
                  progress: {'score': 37, 'activeDays': 2},
                ),
              ],
              'recognitions': [
                {
                  'key': 'CHALLENGE_JOINED_1',
                  'category': 'CHALLENGE',
                  'title': 'Tantangan pertama',
                  'detail': 'd',
                  'achievedAt': '2026-11-10T00:00:00Z',
                },
              ],
              'upcomingRecognitions': [
                {
                  'key': 'REFLECTION_1',
                  'category': 'REFLECTION',
                  'title': 'Refleksi pertama',
                  'detail': 'd',
                },
              ],
              'highlight': null,
              'highlightsEnabled': true,
            });
          case '/api/regions':
            return _json({
              'items': [
                {'code': '73', 'name': 'Sulawesi Selatan', 'level': 'PROVINCE'},
              ],
            });
          case '/api/me/communities':
            return _json({
              'items': [
                {
                  'id': 'c1',
                  'name': 'Hidup Seimbang Sulawesi Selatan',
                  'description': 'Komunitas kebiasaan sehat.',
                  'memberCount': null,
                  'memberCountLabel': 'kurang dari 5',
                  'myStatus': 'NONE',
                  'challenges': [_summary()],
                },
              ],
            });
          case '/api/me/communities/c1/join':
            joinedAlias = (jsonDecode(r.body) as Map)['alias'] as String;
            return _json({
              'created': true,
              'communityId': 'c1',
              'alias': joinedAlias,
            }, 201);
        }
        return _json({}, 404);
      });
      _tall(tester);
      await tester.pumpWidget(_app(repo, const CommunityScreen()));
      await tester.pumpAndSettle();
      expect(find.text('3 hari aktif minggu ini'), findsOneWidget);
      expect(find.text('2 dari 3 hari aktif'), findsOneWidget);
      expect(find.text('Tantangan pertama'), findsOneWidget);
      expect(find.text('Refleksi pertama'), findsOneWidget);
      expect(
        find.text('Hanya kamu yang melihat pencapaian ini.'),
        findsOneWidget,
      );
      expect(find.text('Alias: x90 · 2 tantangan berjalan'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sulawesi Selatan').last);
      await tester.pumpAndSettle();
      expect(find.text('Anggota: kurang dari 5'), findsOneWidget);
      expect(find.textContaining('kurang dari 5 peserta'), findsOneWidget);
      await tester.tap(find.text('Gabung'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Data kesehatan tidak pernah dibagikan'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField).last, 'x');
      await tester.tap(find.text('Gabung dengan alias ini'));
      await tester.pumpAndSettle();
      expect(joinedAlias, isNull);
      await tester.enterText(find.byType(TextField).last, 'Jalan Pagi');
      await tester.tap(find.text('Gabung dengan alias ini'));
      await tester.pumpAndSettle();
      expect(joinedAlias, 'Jalan Pagi');
      expect(seen.where((r) => r.url.path.contains('/leaderboard')), isEmpty);
    },
  );

  testWidgets('Missing community consent shows an explanation, not an error', (
    tester,
  ) async {
    final (repo, _) = await _repo((r) {
      if (r.url.path == '/api/regions') return _json({'items': <dynamic>[]});
      if (r.url.path == '/api/me/community/overview') {
        return _json({
          'consentRequired': true,
          'memberships': [],
          'challenges': [],
          'recognitions': [],
          'upcomingRecognitions': [],
          'highlight': null,
          'highlightsEnabled': true,
        });
      }
      return _json({
        'error': {'code': 'CONSENT_REQUIRED', 'message': 'x'},
      }, 403);
    });
    _tall(tester);
    await tester.pumpWidget(_app(repo, const CommunityScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Persetujuan diperlukan'), findsOneWidget);
    expect(find.text('Buka persetujuan'), findsOneWidget);
  });

  testWidgets(
    'Challenge detail: joining confirms in a sheet with leaderboard visibility off by default, and subscribes to live updates',
    (tester) async {
      bool? sentVisible;
      var joined = false;
      final (repo, _) = await _repo((r) {
        if (r.url.path == '/api/me/challenges/ch1') {
          return _json(_detail(participating: joined));
        }
        if (r.url.path == '/api/me/challenges/ch1/join') {
          sentVisible =
              (jsonDecode(r.body) as Map)['leaderboardVisible'] as bool;
          joined = true;
          return _json({'joined': true}, 201);
        }
        if (r.url.path == '/api/me/challenges/ch1/leaderboard') {
          return _json({
            'suppressed': true,
            'reason':
                'Papan peringkat tampil setelah minimal 5 peserta yang bersedia tampil.',
            'minimumCohort': 5,
            'items': [],
            'me': {'score': 37.0},
          });
        }
        return _json({}, 404);
      });
      _tall(tester);
      await tester.pumpWidget(
        _app(repo, const ChallengeDetailScreen(challengeId: 'ch1')),
      );
      await tester.pumpAndSettle();
      final rt =
          ProviderScope.containerOf(
                tester.element(find.byType(ChallengeDetailScreen)),
              ).read(realtimeProvider.notifier)
              as _QuietRealtime;
      expect(rt.topics, ['challenge:ch1']);
      expect(find.text('Cara kerja'.toUpperCase()), findsOneWidget);
      expect(
        find.textContaining('Tidak ada poin untuk intensitas'),
        findsOneWidget,
      );
      await tester.tap(find.text('Ikut tantangan'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tester.tap(find.text('Ikut tantangan').last);
      await tester.pumpAndSettle();
      expect(sentVisible, isFalse);
      expect(find.text('1 dari 3 hari aktif'), findsOneWidget);
      expect(find.text('Check-in hari ini'), findsOneWidget);
      expect(find.textContaining('minimal 5 peserta'), findsOneWidget);
    },
  );

  testWidgets(
    'Leaderboard shows only alias, rank and score, marks the user, and the visibility switch calls the server',
    (tester) async {
      bool? vis;
      final (repo, _) = await _repo((r) {
        if (r.url.path == '/api/me/challenges/ch1') {
          return _json(_detail(participating: true, visible: true));
        }
        if (r.url.path == '/api/me/challenges/ch1/leaderboard') {
          return _json({
            'suppressed': false,
            'minimumCohort': 5,
            'me': {'score': 40.0, 'visible': true, 'rank': 2},
            'items': [
              {'rank': 1, 'alias': 'Abi', 'score': 55.0, 'isMe': false},
              {'rank': 2, 'alias': 'jalan.pagi', 'score': 40.0, 'isMe': true},
            ],
          });
        }
        if (r.url.path == '/api/me/challenges/ch1/visibility') {
          vis = (jsonDecode(r.body) as Map)['visible'] as bool;
          return _json({'leaderboardVisible': vis});
        }
        return _json({}, 404);
      });
      _tall(tester);
      await tester.pumpWidget(
        _app(repo, const ChallengeDetailScreen(challengeId: 'ch1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Abi'), findsOneWidget);
      expect(find.text('jalan.pagi (kamu)'), findsOneWidget);
      expect(find.text('55'), findsOneWidget);
      expect(find.textContaining('@'), findsNothing);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(vis, isFalse);
    },
  );

  testWidgets(
    'A finished challenge shows the result without a way to join; joining without consent explains what to enable',
    (tester) async {
      final (repo, _) = await _repo((r) {
        if (r.url.path == '/api/me/challenges/ch1') {
          return _json(
            _detail(
              status: 'CLOSED',
              participating: true,
              result: {
                'completionStatus': 'COMPLETED',
                'label': 'Tuntas',
                'finalScore': 100,
                'finalActiveDays': 4,
              },
            ),
          );
        }
        if (r.url.path == '/api/me/challenges/ch1/leaderboard') {
          return _json({
            'suppressed': true,
            'reason': 'r',
            'minimumCohort': 5,
            'items': [],
          });
        }
        if (r.url.path == '/api/me/challenges/ch2') {
          return _json({..._detail(), 'id': 'ch2'});
        }
        if (r.url.path == '/api/me/challenges/ch2/join') {
          return _json({
            'error': {'code': 'CONSENT_REQUIRED', 'message': 'x'},
          }, 403);
        }
        return _json({}, 404);
      });
      _tall(tester);
      await tester.pumpWidget(
        _app(repo, const ChallengeDetailScreen(challengeId: 'ch1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tuntas'), findsOneWidget);
      expect(
        find.text('4 hari aktif dari target 3 · skor 100'),
        findsOneWidget,
      );
      expect(find.text('Ikut tantangan'), findsNothing);
      expect(find.text('Check-in hari ini'), findsNothing);
      await tester.pumpWidget(
        _app(repo, const ChallengeDetailScreen(challengeId: 'ch2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ikut tantangan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ikut tantangan').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Aktifkan persetujuan ikut tantangan di Persetujuan data.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Privacy: lists what is shared and never shared; hiding from all leaderboards and turning off highlights call the server',
    (tester) async {
      var visibleOn = [
        {'challengeId': 'ch1', 'title': '3 hari aktif minggu ini'},
      ];
      var highlights = true;
      final (repo, seen) = await _repo((r) {
        Map<String, dynamic> body() => {
          'memberships': [
            {
              'communityId': 'c1',
              'name': 'Hidup Seimbang Jawa Timur',
              'alias': 'x90',
            },
          ],
          'visibleOn': visibleOn,
          'highlightsEnabled': highlights,
          'shared': ['Alias yang kamu pilih'],
          'neverShared': ['Gula darah, obat, diagnosis, dan ukuran tubuh'],
        };
        if (r.url.path == '/api/me/community/privacy/hide-leaderboards') {
          visibleOn = [];
          return _json(body());
        }
        if (r.url.path == '/api/me/community/privacy' && r.method == 'PATCH') {
          highlights = (jsonDecode(r.body) as Map)['highlightsEnabled'] as bool;
          return _json(body());
        }
        if (r.url.path == '/api/me/community/privacy') return _json(body());
        return _json({}, 404);
      });
      _tall(tester);
      await tester.pumpWidget(_app(repo, const CommunityPrivacyScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('Gula darah'), findsOneWidget);
      expect(
        find.text('Alias di Hidup Seimbang Jawa Timur: x90'),
        findsOneWidget,
      );
      expect(
        find.text('Aliasmu tampil di: 3 hari aktif minggu ini.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Sembunyikan dari semua papan peringkat'));
      await tester.pumpAndSettle();
      expect(
        find.text('Aliasmu tidak tampil di papan peringkat mana pun.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Tampilkan sorotan komunitas di Beranda'));
      await tester.pumpAndSettle();
      expect(highlights, isFalse);
      expect(
        seen.where((r) => r.url.path.endsWith('/hide-leaderboards')),
        hasLength(1),
      );
    },
  );
}
