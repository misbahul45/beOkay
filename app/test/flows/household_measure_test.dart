import 'dart:convert';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/features/nutrition/data/nutrition_models.dart';
import 'package:app/features/nutrition/data/nutrition_repository.dart';
import 'package:app/features/nutrition/presentation/meal_item_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

final _food = FoodReference('f1', 'Nasi putih', 'Uji', 'user_reported', {
  'calories': 130,
  'carbohydrates': 28,
  'protein': 2.7,
  'fat': 0.3,
  'fiber': 0.4,
});

Future<(NutritionRepository, List<http.Request>)> _repo(
  List<Map<String, dynamic>> measures,
) async {
  final tokens = MemoryTokenStorage();
  await tokens.write('t');
  final seen = <http.Request>[];
  return (
    NutritionRepository(
      ApiClient(
        tokens: tokens,
        baseUrl: 'http://test',
        client: MockClient((r) async {
          seen.add(r);
          if (r.url.path == '/api/me/foods/f1/measures' && r.method == 'GET') {
            return _json({'items': measures});
          }
          if (r.url.path == '/api/me/foods/f1/measures' && r.method == 'POST') {
            final b = jsonDecode(r.body) as Map<String, dynamic>;
            final row = {'id': 'm2', 'foodId': 'f1', ...b};
            measures.add(row);
            return _json(row, 201);
          }
          return _json({}, 404);
        }),
      ),
      isCurrentAccount: () => true,
    ),
    seen,
  );
}

Future<MealItemDraft?> _open(
  WidgetTester tester,
  NutritionRepository repo,
  Future<void> Function() interact,
) async {
  MealItemDraft? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () async => result = await showDialog<MealItemDraft>(
              context: ctx,
              builder: (_) => MealItemEditor(food: _food, repository: repo),
            ),
            child: const Text('buka'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('buka'));
  await tester.pumpAndSettle();
  await interact();
  return result;
}

void main() {
  testWidgets(
    'Choosing a saved measure sets total grams = quantity × grams per measure, with its basis',
    (tester) async {
      final (repo, _) = await _repo([
        {
          'id': 'm1',
          'foodId': 'f1',
          'label': '1 centong',
          'grams': 100,
          'basis': 'weighed',
        },
      ]);
      final result = await _open(tester, repo, () async {});
      expect(find.text('1 centong · 100 g'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(1), '1.5');
      await tester.tap(find.text('1 centong · 100 g'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sekitar 150 g (ditimbang)'), findsOneWidget);
      expect(
        find.text('Total gram perkiraan (opsional)'),
        findsNothing,
      ); // gram diturunkan dari ukuran, bukan diketik
      await tester.tap(find.text('Gunakan item'));
      await tester.pumpAndSettle();
      expect(result, isNull); // hasil diambil di bawah
    },
  );

  testWidgets('The saved draft carries grams and the measure basis', (
    tester,
  ) async {
    final (repo, _) = await _repo([
      {
        'id': 'm1',
        'foodId': 'f1',
        'label': '1 centong',
        'grams': 100,
        'basis': 'user_estimate',
      },
    ]);
    MealItemDraft? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () async => picked = await showDialog<MealItemDraft>(
                context: ctx,
                builder: (_) => MealItemEditor(food: _food, repository: repo),
              ),
              child: const Text('buka'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), '2');
    await tester.tap(find.text('1 centong · 100 g'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gunakan item'));
    await tester.pumpAndSettle();
    expect(picked?.grams, 200);
    expect(picked?.gramsBasis, 'user_estimate');
    expect(picked?.foodId, 'f1');
  });

  testWidgets(
    'Without any measure there is no invented conversion; adding one saves it per food and selects it',
    (tester) async {
      final (repo, seen) = await _repo([]);
      await _open(tester, repo, () async {});
      expect(
        find.textContaining('tidak ada tabel konversi umum'),
        findsOneWidget,
      );
      await tester.tap(find.text('Tambah ukuran'));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(AlertDialog).last,
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), '1 sendok makan');
      await tester.enterText(fields.at(1), '15');
      await tester.tap(find.text('Simpan ukuran'));
      await tester.pumpAndSettle();
      final post = seen.firstWhere((r) => r.method == 'POST');
      expect(jsonDecode(post.body), {
        'label': '1 sendok makan',
        'grams': 15,
        'basis': 'user_estimate',
      });
      expect(find.text('1 sendok makan · 15 g'), findsOneWidget);
      expect(find.textContaining('(perkiraanmu)'), findsOneWidget);
    },
  );

  testWidgets(
    'Editor still works with no repository (existing behaviour: manual total grams)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<MealItemDraft>(
                  context: ctx,
                  builder: (_) => MealItemEditor(food: _food),
                ),
                child: const Text('buka'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('buka'));
      await tester.pumpAndSettle();
      expect(find.text('Ukuran rumah tangga'), findsNothing);
      expect(find.text('Total gram perkiraan (opsional)'), findsOneWidget);
    },
  );
}
