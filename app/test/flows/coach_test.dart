import 'dart:convert';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/features/coach/application/coach_controller.dart';
import 'package:app/features/coach/data/coach_repository.dart';
import 'package:app/core/widgets/info_card.dart';
import 'package:app/features/coach/presentation/coach_screen.dart';
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

Map<String, dynamic> _rec(
  String id,
  String name, {
  String status = 'OFFERED',
  int version = 1,
}) => {
  'id': id,
  'runId': 'run1',
  'type': 'NUTRITION',
  'status': status,
  'version': version,
  'title': 'Pertimbangkan: $name',
  'explanation':
      'Pertimbangkan $name: cocok dengan pencarianmu "tempe". Nilai gizi per 100 g bersumber dari Tabel Komposisi Pangan Indonesia.',
  'candidate': {
    'key': 'tkpi:$id',
    'name': name,
    'source': 'Tabel Komposisi Pangan Indonesia',
    'provenance': 'Tabel Komposisi Pangan Indonesia',
    'completeness': 'PARTIAL',
    'origin': 'TKPI',
    'per100g': {
      'calories': 200,
      'carbohydrates': 10,
      'protein': 20,
      'fat': 8,
      'fiber': null,
    },
  },
  'evidenceRefs': [
    {'kind': 'TKPI'},
  ],
  'limitations': [
    'Pengecekan alergi hanya dari nama makanan; bahan lengkap tidak diketahui.',
  ],
  'dataCoverage': 'PARTIAL',
  'policyVersion': 'safety-policy-v1',
  'rankingReason':
      'Urut berdasarkan kecocokan nama, kelengkapan data, dan preferensimu (aturan tetap, bukan model).',
  'requiresConfirmation': true,
  'expiresAt': '2026-11-10T00:00:00.000Z',
};

Map<String, dynamic> _run(
  String status,
  List<Map<String, dynamic>> recs, {
  String? message,
  bool consent = false,
}) => {
  'id': 'run1',
  'status': status,
  'message': message,
  'consentRequired': consent,
  'recommendations': recs,
};

Future<(Widget, List<http.Request>)> _app(
  http.Response Function(http.Request) handler,
) async {
  final tokens = MemoryTokenStorage();
  await tokens.write('t');
  final seen = <http.Request>[];
  final repo = CoachRepository(
    ApiClient(
      tokens: tokens,
      baseUrl: 'http://test',
      client: MockClient((r) async {
        seen.add(r);
        return handler(r);
      }),
    ),
    isCurrentAccount: () => true,
  );
  return (
    ProviderScope(
      overrides: [coachRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: CoachScreen()),
    ),
    seen,
  );
}

http.Response _planned(http.Request r) => _json({'items': <dynamic>[]});

/// Layar tinggi agar seluruh kartu terbangun (ListView malas) tanpa menggulir.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Aliran SSE adalah I/O sungguhan: beri waktu nyata lalu gambar ulang, bukan hanya memajukan jam palsu.
Future<void> _settleStream(WidgetTester tester, {int rounds = 15}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _ask(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.tap(find.text('Cari pilihan'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Shows offered cards with source, nutrients (unknown stays "tidak tersedia"), limitations, and nothing is saved before consent',
    (tester) async {
      final (app, seen) = await _app((r) {
        if (r.url.path == '/api/me/agent/runs' && r.method == 'POST') {
          return _json(
            _run('WAITING_FOR_USER', [
              _rec('r1', 'Tempe bacem'),
            ], message: 'Pilih satu atau tolak.'),
            201,
          );
        }
        if (r.url.path == '/api/me/planned-meals') return _planned(r);
        return _json({}, 404);
      });
      _tall(tester);
      await tester.pumpWidget(app);
      await _ask(tester, 'alternatif pengganti nasi goreng');
      expect(find.text('Pertimbangkan: Tempe bacem'), findsOneWidget);
      expect(
        find.textContaining('Tabel Komposisi Pangan Indonesia'),
        findsWidgets,
      );
      expect(find.text('Serat (g): tidak tersedia'), findsOneWidget);
      expect(find.text('Energi (kkal): 200'), findsOneWidget);
      expect(seen.where((r) => r.url.path.contains('decision')), isEmpty);
      final body =
          jsonDecode(seen.firstWhere((r) => r.method == 'POST').body)
              as Map<String, dynamic>;
      expect(body['message'], 'alternatif pengganti nasi goreng');
      expect(
        (body['idempotencyKey'] as String).length,
        greaterThanOrEqualTo(8),
      );
      expect(find.textContaining('aman'), findsNothing);
    },
  );

  testWidgets(
    'Accepting sends one decision with expectedVersion; a retry after a network failure reuses the same operationId',
    (tester) async {
      var fail = true;
      final ops = <String>[];
      final (app, seen) = await _app((r) {
        if (r.url.path == '/api/me/agent/runs' && r.method == 'POST') {
          return _json(
            _run('WAITING_FOR_USER', [_rec('r1', 'Tempe bacem')]),
            201,
          );
        }
        if (r.url.path == '/api/me/agent/recommendations/r1/decision') {
          ops.add((jsonDecode(r.body) as Map)['operationId'] as String);
          if (fail) {
            fail = false;
            throw http.ClientException('no route');
          }
          return _json({
            'replayed': false,
            'recommendation': _rec(
              'r1',
              'Tempe bacem',
              status: 'ACCEPTED',
              version: 2,
            ),
            'plannedMealId': 'pm1',
          });
        }
        if (r.url.path == '/api/me/agent/runs/run1') {
          return _json(
            _run('COMPLETED', [
              _rec('r1', 'Tempe bacem', status: 'ACCEPTED', version: 2),
            ]),
          );
        }
        if (r.url.path == '/api/me/planned-meals') return _planned(r);
        return _json({}, 404);
      });
      _tall(tester);
      await tester.pumpWidget(app);
      await _ask(tester, 'alternatif tempe');
      await tester.tap(find.text('Simpan ke rencana'));
      await tester.pumpAndSettle();
      expect(
        find.text('Simpan ke rencana'),
        findsOneWidget,
      ); // gagal jaringan: kartu tetap bisa dicoba lagi
      await tester.tap(find.text('Simpan ke rencana'));
      await tester.pumpAndSettle();
      expect(ops, hasLength(2));
      expect(
        ops[0],
        ops[1],
      ); // operationId sama → server tidak menulis dua kali
      expect(
        jsonDecode(
          seen.firstWhere((r) => r.url.path.contains('decision')).body,
        )['expectedVersion'],
        1,
      );
      expect(find.text('Masuk rencana'), findsOneWidget);
    },
  );

  testWidgets('A safety-blocked run shows the policy message and no cards', (
    tester,
  ) async {
    final (app, _) = await _app((r) {
      if (r.url.path == '/api/me/agent/runs') {
        return _json(
          _run(
            'BLOCKED',
            [],
            message:
                'Saya tidak dapat menyarankan perubahan obat atau dosis. Bicarakan dengan dokter atau apotekermu.',
          ),
          201,
        );
      }
      return _planned(r);
    });
    _tall(tester);
    await tester.pumpWidget(app);
    await _ask(tester, 'naikkan dosis metformin');
    expect(
      find.textContaining('tidak dapat menyarankan perubahan obat'),
      findsOneWidget,
    );
    expect(find.text('Simpan ke rencana'), findsNothing);
  });

  testWidgets(
    'Missing AI consent shows an explanation with a way to open consent, not a generic error',
    (tester) async {
      final (app, _) = await _app(
        (r) => r.url.path == '/api/me/agent/runs'
            ? _json({
                'error': {'code': 'CONSENT_REQUIRED', 'message': 'x'},
              }, 403)
            : _planned(r),
      );
      _tall(tester);
      await tester.pumpWidget(app);
      await _ask(tester, 'alternatif tempe');
      expect(find.text('Persetujuan diperlukan'), findsOneWidget);
      expect(find.text('Buka persetujuan'), findsOneWidget);
    },
  );

  testWidgets(
    'Withdrawn consent hides stale cards; a too-short input is rejected locally without a request',
    (tester) async {
      final (app, seen) = await _app(
        (r) => r.url.path == '/api/me/agent/runs'
            ? _json(_run('BLOCKED', [], consent: true), 201)
            : _planned(r),
      );
      _tall(tester);
      await tester.pumpWidget(app);
      await tester.enterText(find.byType(TextField).first, 'a');
      await tester.tap(find.text('Cari pilihan'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tulis makanan'), findsOneWidget);
      expect(seen.where((r) => r.url.path == '/api/me/agent/runs'), isEmpty);
      await _ask(tester, 'alternatif tempe');
      expect(find.textContaining('Persetujuan dicabut'), findsOneWidget);
    },
  );

  testWidgets(
    'Planned meals are listed as plans (not consumption) and feedback goes through the feedback endpoint only',
    (tester) async {
      final (app, seen) = await _app((r) {
        if (r.url.path == '/api/me/planned-meals') {
          return _json({
            'items': [
              {
                'id': 'pm1',
                'recommendationId': 'r9',
                'name': 'Tahu kukus',
                'source': 'TKPI',
                'status': 'PLANNED',
                'version': 1,
              },
            ],
          });
        }
        if (r.url.path == '/api/me/agent/recommendations/r9/feedback') {
          return _json({'replayed': false, 'plannedMeal': {}});
        }
        return _json({}, 404);
      });
      _tall(tester);
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      expect(find.text('Tahu kukus'), findsOneWidget);
      expect(find.textContaining('Direncanakan'), findsOneWidget);
      await tester.ensureVisible(find.text('Sudah dimakan'));
      await tester.tap(find.text('Sudah dimakan'));
      await tester.pumpAndSettle();
      final fb = seen.firstWhere((r) => r.url.path.endsWith('/feedback'));
      expect(jsonDecode(fb.body)['kind'], 'CONSUMED');
      expect(
        seen.where((r) => r.url.path.contains('/meals') && r.method == 'POST'),
        isEmpty,
      ); // tidak membuat catatan makan
    },
  );

  testWidgets(
    'A run that is still running is followed over SSE: progress text shows, and the final state event provides the cards',
    (tester) async {
      _tall(tester);
      final running = {..._run('RUNNING', []), 'id': 'run9'};
      final done = {
        ..._run('WAITING_FOR_USER', [_rec('r1', 'Tempe bacem')]),
        'id': 'run9',
        'turn': 1,
      };
      final sse =
          'retry: 2000\n\n'
          'id: 1\nevent: RUN_CREATED\ndata: ${jsonEncode({'seq': 1, 'type': 'RUN_CREATED', 'payload': {}})}\n\n'
          'id: 2\nevent: NODE_ENTER\ndata: ${jsonEncode({
            'seq': 2,
            'type': 'NODE_ENTER',
            'payload': {'node': 'retrieve_candidates'},
          })}\n\n'
          'event: state\ndata: ${jsonEncode(done)}\n\n';
      final (app, seen) = await _app((r) {
        if (r.url.path == '/api/me/agent/runs' && r.method == 'POST') {
          return _json(running, 202);
        }
        if (r.url.path == '/api/me/agent/runs/run9/stream') {
          return http.Response(
            sse,
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }
        return _planned(r);
      });
      await tester.pumpWidget(app);
      await tester.enterText(find.byType(TextField).first, 'alternatif tempe');
      await tester.tap(find.text('Cari pilihan'));
      await _settleStream(tester);
      expect(
        seen
            .firstWhere(
              (r) => r.method == 'POST' && r.url.path.endsWith('/runs'),
            )
            .url
            .query,
        'async=1',
      );
      expect(find.text('Pertimbangkan: Tempe bacem'), findsOneWidget);
      expect(
        seen.any(
          (r) =>
              r.url.path.endsWith('/stream') &&
              r.headers['Accept'] == 'text/event-stream',
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'If the stream cannot be opened the screen falls back to polling the run instead of failing',
    (tester) async {
      _tall(tester);
      var polls = 0;
      final (app, _) = await _app((r) {
        if (r.url.path == '/api/me/agent/runs' && r.method == 'POST') {
          return _json({..._run('RUNNING', []), 'id': 'run8'}, 202);
        }
        if (r.url.path.endsWith('/stream')) return http.Response('x', 500);
        if (r.url.path == '/api/me/agent/runs/run8') {
          polls++;
          return _json({
            ..._run('WAITING_FOR_USER', [_rec('r1', 'Tahu kukus')]),
            'id': 'run8',
          });
        }
        return _planned(r);
      });
      await tester.pumpWidget(app);
      await tester.enterText(find.byType(TextField).first, 'alternatif tahu');
      await tester.tap(find.text('Cari pilihan'));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(polls, greaterThanOrEqualTo(1));
      expect(find.text('Pertimbangkan: Tahu kukus'), findsOneWidget);
    },
  );

  testWidgets(
    '"Pilihan lain" is a follow-up turn: previousRunId is sent and cards from both turns stay visible; "Kenapa ini?" shows the explanation message',
    (tester) async {
      _tall(tester);
      final bodies = <Map<String, dynamic>>[];
      var n = 0;
      final (app, _) = await _app((r) {
        if (r.url.path == '/api/me/agent/runs' && r.method == 'POST') {
          bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
          n++;
          if (n == 1) {
            return _json({
              ..._run('WAITING_FOR_USER', [_rec('r1', 'Tempe bacem')]),
              'id': 'runA',
              'turn': 1,
            });
          }
          if (n == 2) {
            return _json({
              ..._run('WAITING_FOR_USER', [_rec('r2', 'Tahu kukus')]),
              'id': 'runB',
              'turn': 2,
            });
          }
          return _json({
            ..._run(
              'COMPLETED',
              [],
              message: 'Tempe bacem: Urut berdasarkan kecocokan nama.',
            ),
            'id': 'runC',
            'turn': 3,
            'intent': 'FOLLOW_UP_WHY',
          });
        }
        return _planned(r);
      });
      await tester.pumpWidget(app);
      await _ask(tester, 'alternatif tempe');
      await tester.tap(find.text('Pilihan lain'));
      await tester.pumpAndSettle();
      expect(bodies[1]['previousRunId'], 'runA');
      expect(find.text('Pertimbangkan: Tempe bacem'), findsOneWidget);
      expect(find.text('Pertimbangkan: Tahu kukus'), findsOneWidget);
      await tester.tap(find.text('Kenapa ini?'));
      await tester.pumpAndSettle();
      expect(bodies[2]['previousRunId'], 'runB');
      expect(
        find.textContaining('Urut berdasarkan kecocokan nama.'),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'Text written by the language model is labelled, template text is not; measured outcomes are shown as evidence, separate from self-reported feedback',
    (tester) async {
      _tall(tester);
      final (app, _) = await _app((r) {
        if (r.url.path == '/api/me/agent/runs' && r.method == 'POST') {
          return _json({
            ..._run('WAITING_FOR_USER', [
              {..._rec('r1', 'Tempe bacem'), 'textSource': 'LLM'},
              _rec('r2', 'Tahu kukus'),
            ]),
            'turn': 1,
          });
        }
        if (r.url.path == '/api/me/planned-meals') {
          return _json({
            'items': [
              {
                'id': 'p1',
                'recommendationId': 'r1',
                'name': 'Tempe bacem',
                'source': 'TKPI',
                'status': 'PLANNED',
                'measuredOutcome': {
                  'kind': 'MEAL_LOGGED',
                  'observedAt': '2026-11-10T01:00:00Z',
                },
              },
            ],
          });
        }
        return _json({'items': <dynamic>[]});
      });
      await tester.pumpWidget(app);
      await _ask(tester, 'alternatif tempe');
      expect(
        find.textContaining('Ditulis dengan bantuan AI'),
        findsOneWidget,
      ); // hanya kartu LLM
      expect(
        find.textContaining('Terbukti: makanan serupa tercatat'),
        findsOneWidget,
      );
      expect(
        find.text('Sudah dimakan'),
        findsOneWidget,
      ); // umpan balik sendiri tetap tersedia
    },
  );

  testWidgets(
    'E2E-11: after a restart the screen restores pending runs from the server, in order, with Tolak/Simpan still available',
    (tester) async {
      _tall(tester);
      final (app, seen) = await _app((r) {
        if (r.url.path == '/api/me/agent/pending') {
          return _json({
            'consentRequired': false,
            'items': [
              {
                ..._run('WAITING_FOR_USER', [_rec('r1', 'Tempe bacem')]),
                'id': 'runA',
                'turn': 1,
              },
              {
                ..._run('WAITING_FOR_USER', [_rec('r2', 'Tahu kukus')]),
                'id': 'runB',
                'turn': 2,
              },
            ],
          });
        }
        return _planned(r);
      });
      await tester.pumpWidget(app);
      await _settleStream(tester, rounds: 4);
      expect(seen.any((r) => r.url.path == '/api/me/agent/pending'), isTrue);
      expect(find.text('Pertimbangkan: Tempe bacem'), findsOneWidget);
      expect(find.text('Pertimbangkan: Tahu kukus'), findsOneWidget);
      expect(find.text('Tolak'), findsNWidgets(2));
      expect(find.text('Pilihan lain'), findsOneWidget);
    },
  );

  testWidgets(
    'If restoring pending runs fails the screen simply starts empty (no error banner)',
    (tester) async {
      _tall(tester);
      final (app, _) = await _app(
        (r) => r.url.path == '/api/me/agent/pending'
            ? _json({}, 500)
            : _planned(r),
      );
      await tester.pumpWidget(app);
      await _settleStream(tester, rounds: 4);
      expect(find.text('Cari pilihan'), findsOneWidget);
      expect(find.textContaining('Pertimbangkan'), findsNothing);
      expect(find.byType(ErrorBanner), findsNothing);
    },
  );
}
