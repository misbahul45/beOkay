import 'dart:convert';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/features/memory/application/memory_controller.dart';
import 'package:app/features/memory/data/memory_repository.dart';
import 'package:app/features/memory/presentation/memory_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _item(String id, String content, {int version = 1}) => {
  'id': id,
  'kind': 'ACTIVITY_TIME',
  'kindLabel': 'Waktu aktivitas',
  'content': content,
  'status': 'ACTIVE',
  'version': version,
};

class _Backend {
  bool enabled = true;
  bool consent = true;
  final items = <Map<String, dynamic>>[
    _item('m1', 'Lebih suka beraktivitas pagi hari'),
    _item('m2', 'Punya waktu sekitar 15 menit untuk aktivitas'),
  ];
  final seen = <http.Request>[];

  Map<String, dynamic> overview() => {
    'enabled': enabled,
    'consentGiven': consent,
    'active': enabled && consent,
    'items': items,
  };

  http.Response handle(http.Request r) {
    seen.add(r);
    final path = r.url.path;
    if (path == '/api/me/memories' && r.method == 'GET') {
      return _json(overview());
    }
    if (path == '/api/me/memory-preferences') {
      enabled = (jsonDecode(r.body) as Map)['enabled'] as bool;
      return _json(overview());
    }
    if (path == '/api/me/personalization') {
      return consent
          ? _json({
              'version': 2,
              'dislikedTerms': [
                {'term': 'goreng', 'weight': 1, 'rejections': 2},
              ],
              'likedTerms': <dynamic>[],
            })
          : _json({
              'error': {'code': 'CONSENT_REQUIRED', 'message': 'x'},
            }, 403);
    }
    if (path.startsWith('/api/me/memories/') && r.method == 'PATCH') {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final id = path.split('/').last;
      final i = items.indexWhere((m) => m['id'] == id);
      items[i] = _item(id, body['content'] as String, version: 2);
      return _json(items[i]);
    }
    if (path.startsWith('/api/me/memories/') && r.method == 'DELETE') {
      items.removeWhere((m) => m['id'] == path.split('/').last);
      return _json({'deleted': true});
    }
    if (path == '/api/me/memories' && r.method == 'DELETE') {
      items.clear();
      return _json({'deleted': 2});
    }
    return _json({}, 404);
  }
}

Future<Widget> _app(_Backend b) async {
  final tokens = MemoryTokenStorage();
  await tokens.write('t');
  final repo = MemoryRepository(
    ApiClient(
      tokens: tokens,
      baseUrl: 'http://test',
      client: MockClient((r) async => b.handle(r)),
    ),
    isCurrentAccount: () => true,
  );
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const MemoryScreen()),
      GoRoute(
        path: '/settings/consent',
        builder: (_, _) => const Scaffold(body: Text('Halaman persetujuan')),
      ),
      GoRoute(
        path: '/profile/food-preferences',
        builder: (_, _) => const Scaffold(body: Text('Halaman preferensi')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [memoryRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router),
  );
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets(
    'Lists what is remembered and what else shapes suggestions; editing sends the version; deleting asks first',
    (tester) async {
      _tall(tester);
      final b = _Backend();
      await tester.pumpWidget(await _app(b));
      await tester.pumpAndSettle();
      expect(find.text('Lebih suka beraktivitas pagi hari'), findsOneWidget);
      expect(
        find.text('Punya waktu sekitar 15 menit untuk aktivitas'),
        findsOneWidget,
      );
      expect(find.text('Diturunkan: goreng'), findsOneWidget);
      expect(find.text('Preferensi & alergi makanan'), findsOneWidget);

      await tester.tap(find.byTooltip('Ubah ingatan'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Lebih suka beraktivitas sore hari',
      );
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      final patch = b.seen.firstWhere((r) => r.method == 'PATCH');
      expect(jsonDecode(patch.body), {
        'content': 'Lebih suka beraktivitas sore hari',
        'expectedVersion': 1,
      });
      expect(find.text('Lebih suka beraktivitas sore hari'), findsOneWidget);

      await tester.tap(
        find.text('Punya waktu sekitar 15 menit untuk aktivitas'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('RIWAYAT · PUNYA WAKTU SEKITAR 15 MENIT UNTUK AKTIVITAS'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Hapus ingatan'));
      await tester.pumpAndSettle();
      expect(find.text('Hapus ingatan ini?'), findsOneWidget);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(b.seen.where((r) => r.method == 'DELETE'), isEmpty);
      await tester.tap(find.byTooltip('Hapus ingatan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hapus').last);
      await tester.pumpAndSettle();
      expect(b.seen.where((r) => r.method == 'DELETE'), hasLength(1));
      expect(
        find.text('Punya waktu sekitar 15 menit untuk aktivitas'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Pausing memory sends the preference and explains what it means',
    (tester) async {
      _tall(tester);
      final b = _Backend();
      await tester.pumpWidget(await _app(b));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(
        jsonDecode(
          b.seen
              .firstWhere((r) => r.url.path == '/api/me/memory-preferences')
              .body,
        ),
        {'enabled': false},
      );
      expect(
        find.textContaining('tidak ada yang ditambah atau dipakai'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Without personal-suggestion consent the screen says memory is unused and offers the consent screen; items stay deletable',
    (tester) async {
      _tall(tester);
      final b = _Backend()..consent = false;
      await tester.pumpWidget(await _app(b));
      await tester.pumpAndSettle();
      expect(find.text('Ingatan tidak dipakai'), findsOneWidget);
      expect(
        find.text('Tidak tersedia tanpa persetujuan saran personal.'),
        findsOneWidget,
      );
      expect(find.byTooltip('Hapus ingatan'), findsOneWidget);
      expect(find.text('Jeda'), findsNWidgets(2));
      await tester.tap(find.text('Buka persetujuan'));
      await tester.pumpAndSettle();
      expect(find.text('Halaman persetujuan'), findsOneWidget);
    },
  );

  testWidgets('Delete all asks first and clears the list', (tester) async {
    _tall(tester);
    final b = _Backend();
    await tester.pumpWidget(await _app(b));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus semua ingatan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus semua'));
    await tester.pumpAndSettle();
    expect(b.items, isEmpty);
    expect(find.textContaining('asisten akan bertanya dulu'), findsOneWidget);
  });
}
