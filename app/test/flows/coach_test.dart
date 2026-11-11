import 'dart:convert';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/features/coach/application/coach_controller.dart';
import 'package:app/features/coach/data/coach_repository.dart';
import 'package:app/features/coach/presentation/coach_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _item(
  String id,
  String name, {
  String status = 'OFFERED',
  String match = 'EXACT',
  num? calories = 168,
  bool llm = false,
}) => {
  'id': id,
  'version': 1,
  'status': status,
  'type': 'NUTRITION',
  'name': name,
  'match': match,
  'source': 'Tabel Komposisi Pangan Indonesia',
  'provenance': 'Tabel Komposisi Pangan Indonesia',
  'completeness': 'PARTIAL',
  'per100g': {
    'calories': calories,
    'carbohydrates': 25.6,
    'protein': 3.2,
    'fat': 5.6,
    'fiber': null,
  },
  'activity': null,
  'explanation': 'Pertimbangkan $name: cocok dengan pencarianmu.',
  'rankingReason': 'Diurutkan dari yang paling cocok.',
  'limitations': [
    'Alergi hanya dicek dari nama makanan, bukan bahan lengkapnya.',
  ],
  'writtenByModel': llm,
  'expiresAt': '2026-11-11T00:00:00.000Z',
};

Map<String, dynamic> _msg(
  String id,
  int seq,
  String role, {
  String? text,
  List<Map<String, dynamic>> parts = const [],
}) => {
  'id': id,
  'seq': seq,
  'role': role,
  'text': text,
  'clientMessageId': role == 'USER' ? 'c$id' : null,
  'route': role == 'USER' ? null : 'FOOD',
  'parts': parts,
  'createdAt': '2026-11-10T10:00:00.000Z',
};

Map<String, dynamic> _thread(String id, {DateTime? at, String? title}) => {
  'id': id,
  'title': title ?? 'Percakapan',
  'messageCount': 2,
  'lastMessageAt': (at ?? DateTime.now()).toUtc().toIso8601String(),
  'createdAt': '2026-11-10T10:00:00.000Z',
};

Map<String, dynamic> _exchange(
  String threadId,
  String text,
  List<Map<String, dynamic>> parts, {
  String id = 'a1',
}) => {
  'replayed': false,
  'thread': _thread(threadId),
  'userMessage': _msg('u$id', 1, 'USER', text: text),
  'assistantMessage': _msg(id, 2, 'ASSISTANT', parts: parts),
};

Map<String, dynamic> _recs(
  List<Map<String, dynamic>> items, {
  bool hidden = false,
}) => {
  'type': 'recommendations',
  'runId': 'run1',
  'kind': 'NUTRITION',
  'recommendationIds': [for (final i in items) i['id']],
  'hidden': hidden,
  'items': items,
};

bool _isSend(http.Request r) =>
    r.method == 'POST' && r.url.path.endsWith('/messages');

Future<(Widget, List<http.Request>)> _app(
  http.Response? Function(http.Request) handler,
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
        final res = handler(r);
        if (res != null) return res;
        if (r.url.path == '/api/me/conversations' && r.method == 'GET') {
          return _json({'items': <dynamic>[]});
        }
        if (r.url.path == '/api/me/planned-meals' ||
            r.url.path == '/api/me/activity-plans') {
          return _json({'items': <dynamic>[]});
        }
        return _json({}, 404);
      }),
    ),
    isCurrentAccount: () => true,
  );
  return (
    ProviderScope(
      overrides: [
        coachRepositoryProvider.overrideWithValue(repo),
        tokenStorageProvider.overrideWithValue(MemoryTokenStorage()),
      ],
      child: const MaterialApp(home: Scaffold(body: CoachScreen())),
    ),
    seen,
  );
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.byTooltip('Kirim'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets(
    'Empty state offers starters; tapping one sends a single message and renders the statistic answer without analysis metadata',
    (tester) async {
      _tall(tester);
      final (app, seen) = await _app((r) {
        if (_isSend(r)) {
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          return _json(
            _exchange(r.url.pathSegments[3], body['text'] as String, [
              {
                'type': 'text',
                'text':
                    'Dalam 7 hari terakhir kamu mencatat 80 menit aktivitas di 3 hari.',
              },
              {
                'type': 'statistic',
                'statisticId': 'activity.total_minutes',
                'domain': 'activity',
                'label': 'Aktivitas tercatat · 7 hari',
                'value': 80,
                'unit': 'menit',
                'caption': '3 hari ada catatan',
                'days': 7,
              },
              {'type': 'link', 'label': 'Lihat tren', 'target': 'INSIGHTS'},
            ]),
            201,
          );
        }
        return null;
      });
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      expect(find.text('Mau mulai dari mana?'), findsOneWidget);
      await tester.tap(find.text('Bagaimana aktivitasku minggu ini?'));
      await tester.pumpAndSettle();
      final sends = seen.where(_isSend).toList();
      expect(sends, hasLength(1));
      final body = jsonDecode(sends.single.body) as Map<String, dynamic>;
      expect(body['text'], 'Bagaimana aktivitasku minggu ini?');
      expect(body['clientMessageId'], isNotEmpty);
      expect(find.textContaining('80 menit aktivitas'), findsOneWidget);
      expect(find.text('Aktivitas tercatat · 7 hari'), findsOneWidget);
      expect(find.text('3 hari ada catatan'), findsOneWidget);
      expect(find.text('Lihat tren'), findsOneWidget);
      expect(find.textContaining('stats-v1'), findsNothing);
      expect(find.text('Mau mulai dari mana?'), findsNothing);
    },
  );

  testWidgets(
    'Food result is compact: one primary card, others behind "Lihat pilihan lain"; the detail sheet shows sourced values and unknowns; nothing is decided before the user acts',
    (tester) async {
      _tall(tester);
      final (app, seen) = await _app((r) {
        if (_isSend(r)) {
          return _json(
            _exchange(r.url.pathSegments[3], 'nasi goreng', [
              {
                'type': 'text',
                'text': 'Ini yang paling sesuai dengan pencarianmu.',
              },
              _recs([
                _item('r1', 'Nasi goreng'),
                _item('r2', 'Nasi uduk', match: 'CLOSE', llm: true),
                _item('r3', 'Nasi kuning', match: 'CLOSE', calories: null),
              ]),
            ]),
            201,
          );
        }
        return null;
      });
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await _type(tester, 'nasi goreng');
      expect(find.text('Nasi goreng'), findsOneWidget);
      expect(find.text('Paling sesuai dengan pencarianmu'), findsOneWidget);
      expect(find.text('Energi 168 kkal per 100 g'), findsOneWidget);
      expect(find.text('Nasi uduk'), findsNothing);
      await tester.tap(find.text('Lihat 2 pilihan lain'));
      await tester.pumpAndSettle();
      expect(find.text('Nasi uduk'), findsOneWidget);
      expect(find.text('Mirip dengan pencarianmu'), findsNWidgets(2));
      expect(find.text('Energi belum diketahui'), findsOneWidget);

      await tester.tap(find.text('Lihat detail').first);
      await tester.pumpAndSettle();
      expect(find.text('Nilai per 100 g · data sebagian'), findsOneWidget);
      expect(find.text('25,6 g'), findsOneWidget);
      expect(find.text('tidak diketahui'), findsOneWidget);
      expect(
        find.text('Sumber: Tabel Komposisi Pangan Indonesia'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Alergi hanya dicek dari nama'),
        findsOneWidget,
      );
      expect(find.text('Ditulis dengan bantuan AI.'), findsNothing);
      expect(find.text('Lewati'), findsOneWidget);
      expect(seen.where((r) => r.url.path.contains('/decision')), isEmpty);
    },
  );

  testWidgets(
    'Accepting sends one decision with expectedVersion; a retry after a network failure reuses the same operationId; the refreshed card shows it is in the plan',
    (tester) async {
      _tall(tester);
      var decisions = 0;
      var accepted = false;
      const threadId = 'th1';
      List<Map<String, dynamic>> parts() => [
        _recs([
          _item('r1', 'Tempe bacem', status: accepted ? 'ACCEPTED' : 'OFFERED'),
        ]),
      ];
      final (app, seen) = await _app((r) {
        if (r.url.path == '/api/me/conversations' && r.method == 'GET') {
          return _json({
            'items': [_thread(threadId)],
          });
        }
        if (r.url.path == '/api/me/conversations/$threadId') {
          return _json({
            'thread': _thread(threadId),
            'messages': [
              _msg('u1', 1, 'USER', text: 'tempe'),
              _msg('a1', 2, 'ASSISTANT', parts: parts()),
            ],
          });
        }
        if (r.url.path.endsWith('/r1/decision')) {
          decisions++;
          if (decisions == 1) throw http.ClientException('offline');
          accepted = true;
          return _json({'replayed': false, 'recommendation': {}});
        }
        return null;
      });
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      expect(find.text('Tempe bacem'), findsOneWidget);
      await tester.tap(find.text('Tambahkan ke rencana'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Masuk rencana'), findsNothing);
      await tester.tap(find.text('Tambahkan ke rencana'));
      await tester.pumpAndSettle();
      final sent = seen
          .where((r) => r.url.path.endsWith('/decision'))
          .map((r) => jsonDecode(r.body) as Map<String, dynamic>)
          .toList();
      expect(sent, hasLength(2));
      expect(sent[0]['operationId'], sent[1]['operationId']);
      expect(sent[0]['decision'], 'ACCEPT');
      expect(sent[0]['expectedVersion'], 1);
      expect(find.text('Masuk rencana'), findsOneWidget);
      expect(find.text('Tambahkan ke rencana'), findsNothing);
    },
  );

  testWidgets(
    'A failed send keeps the message with "Coba lagi"; retrying reuses the same clientMessageId',
    (tester) async {
      _tall(tester);
      var attempts = 0;
      final (app, seen) = await _app((r) {
        if (_isSend(r)) {
          attempts++;
          if (attempts == 1) throw http.ClientException('offline');
          return _json(
            _exchange(r.url.pathSegments[3], 'halo', [
              {'type': 'text', 'text': 'Halo! Mau mulai dari mana?'},
            ]),
            201,
          );
        }
        return null;
      });
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await _type(tester, 'halo');
      expect(find.text('Coba lagi'), findsOneWidget);
      expect(find.text('halo'), findsOneWidget);
      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      final ids = seen
          .where(_isSend)
          .map((r) => (jsonDecode(r.body) as Map)['clientMessageId'])
          .toList();
      expect(ids, hasLength(2));
      expect(ids[0], ids[1]);
      expect(find.text('Halo! Mau mulai dari mana?'), findsOneWidget);
      expect(find.text('Coba lagi'), findsNothing);
    },
  );

  testWidgets(
    'Safety, consent, withdrawn-consent, and no-match answers render as their own cards without recommendation actions',
    (tester) async {
      _tall(tester);
      var n = 0;
      final replies = [
        [
          {
            'type': 'safety',
            'code': 'MEDICATION_ADVICE',
            'title': 'Perlu tenaga kesehatan',
            'text': 'Saya tidak dapat menyarankan perubahan obat atau dosis.',
            'urgent': false,
          },
        ],
        [
          {
            'type': 'consent_required',
            'purpose': 'personalized_ai',
            'text':
                'Untuk ini, aktifkan "Saran personal dari asisten beOkay" di Persetujuan data.',
          },
        ],
        [
          _recs([_item('r1', 'Tempe bacem')], hidden: true)
            ..['items'] = <dynamic>[],
        ],
        [
          {
            'type': 'no_match',
            'query': 'gendar goreng',
            'text':
                'Belum menemukan makanan yang cocok dengan "gendar goreng".',
          },
        ],
      ];
      final (app, _) = await _app((r) {
        if (_isSend(r)) {
          final i = n++;
          return _json(
            _exchange(r.url.pathSegments[3], 'x', replies[i].cast(), id: 'a$i'),
            201,
          );
        }
        return null;
      });
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await _type(tester, 'naikkan dosis');
      expect(find.text('Perlu tenaga kesehatan'), findsOneWidget);
      await _type(tester, 'cari tempe');
      expect(find.text('Persetujuan diperlukan'), findsOneWidget);
      expect(find.text('Buka persetujuan'), findsOneWidget);
      await _type(tester, 'tempe lagi');
      expect(
        find.text(
          'Persetujuan dicabut, jadi saran ini tidak dapat dilanjutkan.',
        ),
        findsOneWidget,
      );
      await _type(tester, 'gendar goreng');
      expect(find.text('Makanan belum ditemukan'), findsOneWidget);
      expect(find.text('Tambahkan ke rencana'), findsNothing);
      await tester.tap(find.text('Ubah pencarian'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'gendar goreng',
      );
    },
  );

  testWidgets(
    'Suggestion chips appear only on the latest answer and tapping one sends its message',
    (tester) async {
      _tall(tester);
      var n = 0;
      final (app, seen) = await _app((r) {
        if (_isSend(r)) {
          final i = n++;
          return _json(
            _exchange(r.url.pathSegments[3], 'x', [
              {'type': 'text', 'text': 'Jawaban $i'},
              {
                'type': 'suggestions',
                'items': [
                  {'label': 'Saran $i', 'message': 'pesan saran $i'},
                ],
              },
            ], id: 'a$i'),
            201,
          );
        }
        return null;
      });
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await _type(tester, 'halo');
      expect(find.text('Saran 0'), findsOneWidget);
      await tester.tap(find.text('Saran 0'));
      await tester.pumpAndSettle();
      expect(find.text('Saran 0'), findsNothing);
      expect(find.text('Saran 1'), findsOneWidget);
      final last = jsonDecode(seen.where(_isSend).last.body) as Map;
      expect(last['text'], 'pesan saran 0');
    },
  );

  testWidgets(
    'After a restart the latest recent conversation is restored; an old one is not; a failed restore just shows the empty state',
    (tester) async {
      _tall(tester);
      final (app, _) = await _app((r) {
        if (r.url.path == '/api/me/conversations' && r.method == 'GET') {
          return _json({
            'items': [_thread('recent', title: 'tempe')],
          });
        }
        if (r.url.path == '/api/me/conversations/recent') {
          return _json({
            'thread': _thread('recent'),
            'messages': [
              _msg('u1', 1, 'USER', text: 'tempe'),
              _msg(
                'a1',
                2,
                'ASSISTANT',
                parts: [
                  _recs([_item('r1', 'Tempe bacem')]),
                ],
              ),
            ],
          });
        }
        return null;
      });
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      expect(find.text('Tempe bacem'), findsOneWidget);
      expect(find.text('Tambahkan ke rencana'), findsOneWidget);

      final (old, _) = await _app((r) {
        if (r.url.path == '/api/me/conversations' && r.method == 'GET') {
          return _json({
            'items': [
              _thread(
                'old',
                at: DateTime.now().subtract(const Duration(days: 3)),
              ),
            ],
          });
        }
        return null;
      });
      await tester.pumpWidget(old);
      await tester.pumpAndSettle();
      expect(find.text('Mau mulai dari mana?'), findsOneWidget);

      final (broken, _) = await _app((r) {
        if (r.url.path == '/api/me/conversations' && r.method == 'GET') {
          return _json({
            'error': {'code': 'X', 'message': 'gagal'},
          }, 500);
        }
        return null;
      });
      await tester.pumpWidget(broken);
      await tester.pumpAndSettle();
      expect(find.text('Mau mulai dari mana?'), findsOneWidget);
      expect(find.text('Coba lagi'), findsNothing);
    },
  );

  testWidgets(
    'History sheet lists conversations and plans; plan feedback uses the feedback endpoint only; deleting a conversation asks first and sends DELETE',
    (tester) async {
      _tall(tester);
      final (app, seen) = await _app((r) {
        if (r.url.path == '/api/me/conversations' && r.method == 'GET') {
          return _json({
            'items': [
              _thread(
                'th9',
                title: 'Cari info tahu',
                at: DateTime.now().subtract(const Duration(days: 2)),
              ),
            ],
          });
        }
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
          return _json({'replayed': false});
        }
        if (r.method == 'DELETE') {
          return _json({'deleted': true, 'id': 'th9', 'messages': 2});
        }
        return null;
      });
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Riwayat & rencana'));
      await tester.pumpAndSettle();
      expect(find.text('Cari info tahu'), findsOneWidget);
      expect(find.text('Tahu kukus'), findsOneWidget);
      expect(find.textContaining('Direncanakan'), findsOneWidget);
      await tester.tap(find.text('Sudah dimakan'));
      await tester.pumpAndSettle();
      final fb = seen.firstWhere((r) => r.url.path.endsWith('/feedback'));
      expect(jsonDecode(fb.body)['kind'], 'CONSUMED');
      expect(
        seen.where((r) => r.url.path.contains('/meals') && r.method == 'POST'),
        isEmpty,
      );

      await tester.tap(find.byTooltip('Hapus percakapan'));
      await tester.pumpAndSettle();
      expect(find.text('Hapus percakapan ini?'), findsOneWidget);
      await tester.tap(find.text('Hapus'));
      await tester.pumpAndSettle();
      final del = seen.where((r) => r.method == 'DELETE').toList();
      expect(del, hasLength(1));
      expect(del.single.url.path, '/api/me/conversations/th9');
    },
  );
}
