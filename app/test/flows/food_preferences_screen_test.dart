import 'dart:convert';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/features/food_preferences/application/food_preferences_controller.dart';
import 'package:app/features/food_preferences/data/food_preferences_repository.dart';
import 'package:app/features/food_preferences/presentation/food_preferences_screen.dart';
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

Future<(Widget, List<Map<String, dynamic>>, List<http.Request>)> _app() async {
  final tokens = MemoryTokenStorage();
  await tokens.write('t');
  final store = <Map<String, dynamic>>[];
  final seen = <http.Request>[];
  final repo = FoodPreferencesRepository(
    ApiClient(
      tokens: tokens,
      baseUrl: 'http://test',
      client: MockClient((r) async {
        seen.add(r);
        if (r.url.path == '/api/me/food-preferences' && r.method == 'GET') {
          return _json({
            'items': store.where((p) => p['archived'] != true).toList(),
          });
        }
        if (r.url.path == '/api/me/food-preferences' && r.method == 'POST') {
          final b = jsonDecode(r.body) as Map<String, dynamic>;
          final row = {
            'id': 'p${store.length + 1}',
            'kind': b['kind'],
            'term': b['term'],
            'label':
                (b['term'] as String)[0].toUpperCase() +
                (b['term'] as String).substring(1),
            'severity': b['kind'] == 'allergy' || b['kind'] == 'restriction'
                ? 'strict'
                : 'soft',
            'version': 1,
          };
          store.add(row);
          return _json(row, 201);
        }
        if (r.method == 'PATCH') {
          final id = r.url.pathSegments.last;
          store.firstWhere((p) => p['id'] == id)['archived'] = true;
          return _json({'id': id});
        }
        return _json({}, 404);
      }),
    ),
    isCurrentAccount: () => true,
  );
  return (
    ProviderScope(
      overrides: [
        foodPreferencesRepositoryProvider.overrideWithValue(repo),
        foodPreferencesProvider.overrideWith(
          (ref) => ref.watch(foodPreferencesRepositoryProvider).list(),
        ),
      ],
      child: const MaterialApp(home: FoodPreferencesScreen()),
    ),
    store,
    seen,
  );
}

void main() {
  testWidgets(
    'Empty state, disclaimer, add an allergy by quick pick, then remove it',
    (tester) async {
      final (app, store, seen) = await _app();
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Tetap baca label bila kamu alergi'),
        findsOneWidget,
      ); // satu baris, bukan kotak
      expect(find.text('Belum ada yang dicatat'), findsOneWidget);

      await tester.tap(find.text('Tambah').last);
      await tester.pumpAndSettle();
      expect(find.text('Pilihan cepat'), findsOneWidget);
      await tester.tap(find.text('Kacang').first);
      await tester.pumpAndSettle();
      expect(store.single['kind'], 'allergy');
      expect(store.single['term'], 'kacang');
      expect(find.text('ALERGI'), findsOneWidget);
      expect(
        find.text('Kendala keras: dikecualikan di pencarian'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Hapus Kacang'));
      await tester.pumpAndSettle();
      expect(
        seen.where((r) => r.method == 'PATCH').single.body,
        contains('"archived":true'),
      );
      expect(find.text('Belum ada yang dicatat'), findsOneWidget);
    },
  );

  testWidgets(
    'A dislike is soft and a too-short term is rejected without a request',
    (tester) async {
      final (app, store, seen) = await _app();
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tambah').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tidak suka'));
      await tester.pumpAndSettle();
      expect(find.text('Pilihan cepat'), findsNothing);
      await tester.enterText(find.byType(TextField).last, 'p');
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(find.text('Isi minimal dua karakter.'), findsOneWidget);
      expect(seen.where((r) => r.method == 'POST'), isEmpty);

      await tester.enterText(find.byType(TextField).last, 'pare');
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(store.single['severity'], 'soft');
      expect(find.text('TIDAK SUKA'), findsOneWidget);
      expect(find.text('Peringatan lunak'), findsOneWidget);
    },
  );
}
