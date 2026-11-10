import 'dart:convert';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/features/food_preferences/data/food_preferences_repository.dart';
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

Map<String, dynamic> _food(String id, String name) => {
  'id': id,
  'name': name,
  'source': 'Uji',
  'status': 'user_reported',
  'per100g': {
    'calories': 100,
    'carbohydrates': 10,
    'protein': 5,
    'fat': 2,
    'fiber': 1,
  },
};

const _tkpi = {
  'code': 'KP001',
  'name': 'Kacang tanah goreng',
  'source': 'Tabel Komposisi Pangan Indonesia',
  'provenance': 'Tabel Komposisi Pangan Indonesia',
  'completeness': 'PARTIAL',
  'per100g': {
    'calories': 560,
    'carbohydrates': 20,
    'protein': 28,
    'fat': 45,
    'fiber': null,
  },
};

http.Response _handler(
  http.Request r, {
  bool withReference = true,
  bool strict = true,
}) {
  switch (r.url.path) {
    case '/api/foods/search':
      return _json({
        'items': [_food('f1', 'Selai kacang'), _food('f2', 'Roti tawar')],
      });
    case '/api/me/foods/reference':
      return withReference
          ? _json({
              'status': 'OK',
              'items': [_tkpi],
            })
          : _json({}, 500);
    case '/api/me/food-preferences/check':
      final names = [
        for (final i in (jsonDecode(r.body)['items'] as List))
          (i as Map)['name'] as String,
      ];
      return _json({
        'hasStrictConstraints': strict,
        'results': [
          for (final n in names)
            {
              'name': n,
              'status': strict && n.toLowerCase().contains('kacang')
                  ? 'EXCLUDED'
                  : 'NO_MATCH_FOUND',
              'matches': strict && n.toLowerCase().contains('kacang')
                  ? [
                      {
                        'label': 'Kacang',
                        'severity': 'strict',
                        'basis': 'NAME',
                      },
                    ]
                  : [],
              'note': '',
            },
        ],
      });
    case '/api/me/foods':
      final b = jsonDecode(r.body) as Map<String, dynamic>;
      return _json({
        'id': 'saved',
        'name': b['name'],
        'source': b['source'],
        'status': 'estimated',
        'per100g': b['per100g'],
      }, 201);
  }
  return _json({}, 404);
}

Future<void> _open(
  WidgetTester tester,
  NutritionRepository repo,
  void Function(FoodReference?) onPick,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () async => onPick(await pickFood(ctx, repo)),
            child: const Text('buka'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('buka'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, 'kacang');
  await tester.tap(find.text('Cari'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Picker shows TKPI reference with provenance, flags allergy matches, and never calls anything "safe"',
    (tester) async {
      final (repo, _) = await _repo(_handler);
      await _open(tester, repo, (_) {});
      expect(
        find.text('Dari Tabel Komposisi Pangan Indonesia'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Tabel Komposisi Pangan Indonesia'),
        findsWidgets,
      );
      expect(find.text('Kacang tanah goreng'), findsOneWidget);
      expect(
        find.textContaining('Perhatian: cocok dengan Kacang'),
        findsWidgets,
      );
      expect(find.text('Roti tawar'), findsOneWidget);
      expect(
        find.textContaining('Alergi hanya dicek dari nama makanan'),
        findsOneWidget,
      );
      expect(find.textContaining('aman'), findsNothing);
    },
  );

  testWidgets(
    'Choosing a flagged food asks for confirmation; cancel keeps the picker open, confirm returns the food',
    (tester) async {
      final (repo, _) = await _repo(_handler);
      FoodReference? picked;
      await _open(tester, repo, (f) => picked = f);
      await tester.tap(find.text('Selai kacang'));
      await tester.pumpAndSettle();
      expect(find.text('Cocok dengan kendalamu'), findsOneWidget);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(picked, isNull);
      expect(find.text('Cari makanan'), findsOneWidget);

      await tester.tap(find.text('Selai kacang'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tetap gunakan'));
      await tester.pumpAndSettle();
      expect(picked?.name, 'Selai kacang');
    },
  );

  testWidgets('Unflagged food is picked directly with no dialog', (
    tester,
  ) async {
    final (repo, _) = await _repo(_handler);
    FoodReference? picked;
    await _open(tester, repo, (f) => picked = f);
    await tester.tap(find.text('Roti tawar'));
    await tester.pumpAndSettle();
    expect(find.text('Cocok dengan kendalamu'), findsNothing);
    expect(picked?.name, 'Roti tawar');
  });

  testWidgets(
    'Picking a TKPI row saves an estimate with the code as source version and unknowns kept null',
    (tester) async {
      Map<String, dynamic>? saved;
      final (repo, _) = await _repo((r) {
        if (r.url.path == '/api/me/foods') {
          saved = jsonDecode(r.body) as Map<String, dynamic>;
        }
        return _handler(r, strict: false);
      });
      FoodReference? picked;
      await _open(tester, repo, (f) => picked = f);
      await tester.ensureVisible(find.text('Kacang tanah goreng'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kacang tanah goreng'));
      await tester.pumpAndSettle();
      expect(saved?['status'], 'estimated');
      expect(saved?['sourceVersion'], 'KP001');
      expect(saved?['source'], 'Tabel Komposisi Pangan Indonesia');
      expect((saved?['per100g'] as Map)['fiber'], isNull);
      expect(picked?.name, 'Kacang tanah goreng');
    },
  );

  testWidgets(
    'If the reference or check endpoints fail, the main search still works and no badge is invented',
    (tester) async {
      final (repo, _) = await _repo(
        (r) => r.url.path == '/api/me/food-preferences/check'
            ? _json({}, 500)
            : _handler(r, withReference: false),
      );
      await _open(tester, repo, (_) {});
      expect(find.text('Selai kacang'), findsOneWidget);
      expect(find.text('Dari Tabel Komposisi Pangan Indonesia'), findsNothing);
      expect(find.textContaining('Perhatian'), findsNothing);
    },
  );

  test(
    'PreferenceChecks parsing keeps strict flag and never treats NO_MATCH_FOUND as a match',
    () {
      final c = PreferenceCheck.fromJson({
        'name': 'Nasi',
        'status': 'NO_MATCH_FOUND',
        'matches': <dynamic>[],
      });
      expect(c.noMatch, isTrue);
      expect(c.excluded, isFalse);
      final x = PreferenceCheck.fromJson({
        'name': 'Gado-gado',
        'status': 'EXCLUDED',
        'matches': [
          {'label': 'Kacang', 'severity': 'strict'},
        ],
      });
      expect(x.excluded && x.strictMatch, isTrue);
      expect(x.labels, ['Kacang']);
    },
  );
}
