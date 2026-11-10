import 'dart:convert';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/features/community/application/community_controller.dart';
import 'package:app/features/community/data/community_repository.dart';
import 'package:app/features/community/presentation/challenge_screen.dart';
import 'package:app/features/community/presentation/community_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

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

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 3600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Map<String, dynamic> _challenge({bool participating = false}) => {
  'id': 'ch1',
  'title': 'Aktif 5 hari seminggu',
  'description': 'Hari aktif = ada satu sesi tercatat.',
  'startsOn': '2026-11-09',
  'endsOn': '2026-12-06',
  'targetDays': 20,
  'participating': participating,
  'leaderboardVisible': false,
};

void main() {
  testWidgets(
    'Community screen: regions load, picking a province lists communities with the member count hidden below the cohort minimum, and joining asks for an alias',
    (tester) async {
      String? joinedAlias;
      final (repo, seen) = await _repo((r) {
        if (r.url.path == '/api/regions') {
          return _json({
            'items': [
              {'code': '73', 'name': 'Sulawesi Selatan', 'level': 'PROVINCE'},
              {'code': '31', 'name': 'DKI Jakarta', 'level': 'PROVINCE'},
            ],
          });
        }
        if (r.url.path == '/api/me/communities/mine') {
          return _json({'items': <dynamic>[], 'consentRequired': false});
        }
        if (r.url.path == '/api/me/communities' &&
            r.url.queryParameters['regionCode'] == '73') {
          return _json({
            'items': [
              {
                'id': 'c1',
                'name': 'Hidup Seimbang Sulawesi Selatan',
                'description': 'Komunitas kebiasaan sehat.',
                'memberCount': null,
                'memberCountLabel': 'kurang dari 5',
                'myStatus': 'NONE',
              },
            ],
          });
        }
        if (r.url.path == '/api/me/communities/c1/join') {
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
      await tester.pumpWidget(
        ProviderScope(
          overrides: [communityRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(home: CommunityScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('hanya aliasmu'),
        findsNothing,
      ); // privasi dijelaskan di dialog alias, bukan banner
      expect(
        find.text('Belum bergabung dengan komunitas mana pun.'),
        findsOneWidget,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sulawesi Selatan').last);
      await tester.pumpAndSettle();
      expect(find.text('Anggota: kurang dari 5'), findsOneWidget);
      await tester.tap(find.text('Gabung'));
      await tester.pumpAndSettle();
      expect(find.textContaining('bukan namamu'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Jalan Pagi');
      await tester.tap(find.text('Gabung').last);
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
      return _json({
        'error': {'code': 'CONSENT_REQUIRED', 'message': 'x'},
      }, 403);
    });
    _tall(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [communityRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: CommunityScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Persetujuan diperlukan'), findsOneWidget);
    expect(find.text('Buka persetujuan'), findsOneWidget);
  });

  testWidgets(
    'Joining a challenge is opt-in for leaderboard visibility (off by default) and sends exactly that choice',
    (tester) async {
      bool? sentVisible;
      final (repo, _) = await _repo((r) {
        if (r.url.path == '/api/me/challenges/ch1/join') {
          sentVisible =
              (jsonDecode(r.body) as Map)['leaderboardVisible'] as bool;
          return _json({'joined': true}, 201);
        }
        if (r.url.path == '/api/me/challenges/ch1/progress') {
          return _json({
            'score': 22.5,
            'activityDays': 1,
            'checkinDays': 0,
            'targetDays': 20,
            'leaderboardVisible': false,
            'note': 'Hari tanpa catatan bukan kegagalan: skor hanya bertambah.',
          });
        }
        if (r.url.path == '/api/me/challenges/ch1/leaderboard') {
          return _json({
            'suppressed': true,
            'reason':
                'Papan peringkat tampil setelah minimal 5 peserta yang bersedia tampil.',
            'minimumCohort': 5,
            'items': <dynamic>[],
            'me': {'score': 22.5, 'visible': false},
          });
        }
        return _json({}, 404);
      });
      _tall(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [communityRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            home: ChallengeDetailScreen(
              challenge: Challenge.fromJson(_challenge()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tester.tap(find.text('Ikut tantangan'));
      await tester.pumpAndSettle();
      expect(sentVisible, isFalse);
      expect(find.text('Skormu: 22.5'), findsOneWidget);
      expect(find.textContaining('bukan kegagalan'), findsOneWidget);
      expect(
        find.textContaining('minimal 5 peserta'),
        findsOneWidget,
      ); // kohort kecil: daftar ditekan
    },
  );

  testWidgets(
    'Leaderboard shows only alias, rank and score, marks the user, and the visibility switch calls the server',
    (tester) async {
      bool? vis;
      final (repo, _) = await _repo((r) {
        if (r.url.path == '/api/me/challenges/ch1/progress') {
          return _json({
            'score': 40.0,
            'activityDays': 3,
            'checkinDays': 1,
            'targetDays': 20,
            'leaderboardVisible': true,
            'note': 'n',
          });
        }
        if (r.url.path == '/api/me/challenges/ch1/leaderboard') {
          return _json({
            'suppressed': false,
            'minimumCohort': 5,
            'visibleCount': 5,
            'me': {'score': 40.0, 'visible': true, 'rank': 2},
            'items': [
              {'rank': 1, 'alias': 'Abi', 'score': 55.0, 'isMe': false},
              {'rank': 2, 'alias': 'Kamu1', 'score': 40.0, 'isMe': true},
              {'rank': 3, 'alias': 'Cici', 'score': 20.0, 'isMe': false},
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
        ProviderScope(
          overrides: [communityRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            home: ChallengeDetailScreen(
              challenge: Challenge.fromJson(_challenge(participating: true)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Abi'), findsOneWidget);
      expect(find.text('Kamu1 (kamu)'), findsOneWidget);
      expect(find.text('55.0'), findsOneWidget);
      expect(find.textContaining('@'), findsNothing);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(vis, isFalse);
    },
  );

  testWidgets(
    'Joining without challenge consent shows a card that leads to consent settings',
    (tester) async {
      final (repo, _) = await _repo((r) {
        if (r.url.path == '/api/me/challenges/ch1/join') {
          return _json({
            'error': {'code': 'CONSENT_REQUIRED', 'message': 'x'},
          }, 403);
        }
        return _json({}, 404);
      });
      _tall(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [communityRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            home: ChallengeDetailScreen(
              challenge: Challenge.fromJson(_challenge()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ikut tantangan'));
      await tester.pumpAndSettle();
      expect(find.text('Persetujuan diperlukan'), findsOneWidget);
      expect(find.text('Buka persetujuan'), findsOneWidget);
      expect(find.textContaining('Ikut tantangan kebiasaan'), findsOneWidget);
    },
  );
}
