import 'dart:convert';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/features/nutrition/data/nutrition_models.dart';
import 'package:app/features/nutrition/data/nutrition_repository.dart';
import 'package:app/features/nutrition/presentation/food_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Future<(NutritionRepository, List<http.Request>)> _repo(
  http.Response Function(http.Request) handler,
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
          return handler(r);
        }),
      ),
      isCurrentAccount: () => true,
    ),
    seen,
  );
}

const _candidate = {
  'externalId': '123',
  'name': 'Roti uji',
  'brand': 'Merek A',
  'source': 'Open Food Facts',
  'completeness': 'PARTIAL',
  'per100g': {
    'calories': 260,
    'carbohydrates': 50,
    'protein': null,
    'fat': 3,
    'fiber': null,
  },
};

void main() {
  testWidgets(
    'External search is explicit, labelled, and saves as an estimate with unknowns kept null',
    (tester) async {
      Map<String, dynamic>? saved;
      final (repo, seen) = await _repo((r) {
        if (r.url.path == '/api/foods/search') return _json({'items': []});
        if (r.url.path == '/api/me/foods/discover') {
          return _json({
            'local': [],
            'external': {
              'status': 'PARTIAL',
              'providers': [],
              'items': [_candidate],
            },
          });
        }
        if (r.url.path == '/api/me/foods' && r.method == 'POST') {
          saved = jsonDecode(r.body) as Map<String, dynamic>;
          return _json({
            'id': 'f1',
            'name': saved!['name'],
            'source': saved!['source'],
            'status': 'estimated',
            'per100g': saved!['per100g'],
          }, 201);
        }
        return _json({}, 404);
      });
      FoodReference? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () async => picked = await pickFood(ctx, repo),
                child: const Text('buka'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('buka'));
      await tester.pumpAndSettle();
      expect(
        find.text('Cari juga di sumber luar'),
        findsNothing,
      ); // only after a local search

      await tester.enterText(find.byType(TextField).first, 'roti');
      await tester.tap(find.text('Cari'));
      await tester.pumpAndSettle();
      expect(
        seen.any((r) => r.url.path == '/api/me/foods/discover'),
        isFalse,
      ); // nothing left the server yet
      expect(find.textContaining('Open Food Facts dan USDA'), findsOneWidget);

      await tester.tap(find.text('Cari juga di sumber luar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sebagian sumber luar'), findsOneWidget);
      expect(find.text('Roti uji · Merek A'), findsOneWidget);
      expect(find.textContaining('Data gizi sebagian'), findsOneWidget);

      await tester.tap(find.text('Roti uji · Merek A'));
      await tester.pumpAndSettle();
      expect(saved!['status'], 'estimated');
      expect(saved!['source'], 'Open Food Facts');
      expect(saved!['sourceVersion'], '123');
      expect(
        (saved!['per100g'] as Map)['protein'],
        isNull,
      ); // unknown is not zero
      expect(picked?.id, 'f1');
    },
  );
}
