import 'package:app/features/nutrition/data/nutrition_models.dart';
import 'package:app/features/nutrition/presentation/meal_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/network/api_client.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/features/nutrition/data/nutrition_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app/features/nutrition/application/nutrition_controller.dart';
import 'package:app/features/nutrition/presentation/meal_history_screen.dart';
import 'package:app/core/widgets/app_text_field.dart';

void main() {
  testWidgets('Meal validation error leaves fields editable', (tester) async {
    await initializeDateFormatting('id_ID');
    final tokens = MemoryTokenStorage();
    await tokens.write(newRecordId());
    final repo = NutritionRepository(
      ApiClient(
        client: MockClient(
          (_) async => http.Response(
            '{"error":{"code":"VALIDATION_ERROR","message":"invalid"}}',
            400,
          ),
        ),
        tokens: tokens,
        baseUrl: 'http://test',
      ),
      isCurrentAccount: () => true,
    );
    final record = MealRecord(
      id: newRecordId(),
      category: 'lunch',
      consumedAt: DateTime.now().subtract(const Duration(hours: 1)),
      localDate: '2026-11-08',
      localTime: '12:00',
      timezone: 'Asia/Jakarta',
      version: 1,
      items: [
        const MealItemDraft(name: 'Unknown', quantity: 1, unit: 'portion'),
      ],
      totals: {},
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => MealFormScreen(initial: record),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [nutritionRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    Finder input(String label) => find.descendant(
      of: find.byWidgetPredicate((w) => w is AppTextField && w.label == label),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(input('Alasan koreksi'));
    await tester.enterText(input('Alasan koreksi'), 'Test validation');
    await tester.ensureVisible(find.text('Simpan koreksi'));
    await tester.tap(find.text('Simpan koreksi'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(input('Catatan (opsional)')).enabled,
      isTrue,
    );
  });
  testWidgets('Typing only notes still protects unsaved meal changes', (
    tester,
  ) async {
    await initializeDateFormatting('id_ID');
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/new'),
              child: const Text('Open meal'),
            ),
          ),
        ),
        GoRoute(path: '/new', builder: (_, _) => const MealFormScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open meal'));
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: find.byWidgetPredicate(
        (w) => w is AppTextField && w.label == 'Catatan (opsional)',
      ),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Unsaved meal note');
    await tester.pump();
    await tester.tap(find.byTooltip('Kembali'));
    await tester.pumpAndSettle();
    expect(find.text('Buang perubahan?'), findsOneWidget);
  });
  testWidgets('Meal history opened as root can return to Today', (
    tester,
  ) async {
    final repo = NutritionRepository(
      ApiClient(
        client: MockClient((_) async => http.Response('{}', 200)),
        tokens: MemoryTokenStorage(),
      ),
      isCurrentAccount: () => true,
    );
    final router = GoRouter(
      initialLocation: '/meals',
      routes: [
        GoRoute(path: '/meals', builder: (_, _) => const MealHistoryScreen()),
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('Today destination')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nutritionRepositoryProvider.overrideWithValue(repo),
          mealPageProvider.overrideWith(
            (ref, arg) async => const MealPage([], null, 'Asia/Jakarta'),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Kembali'), findsOneWidget);
    await tester.tap(find.byTooltip('Kembali'));
    await tester.pumpAndSettle();
    expect(find.text('Today destination'), findsOneWidget);
  });
  test(
    'Nutrition write captures the acting session across account switching',
    () async {
      final tokens = MemoryTokenStorage();
      final acting = newRecordId(), next = newRecordId();
      await tokens.write(acting);
      final client = MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer $acting');
        await tokens.write(next);
        return http.Response('{}', 200);
      });
      final repo = NutritionRepository(
        ApiClient(client: client, tokens: tokens, baseUrl: 'http://test'),
        isCurrentAccount: () => true,
      );
      await repo.write('POST', '/api/me/meals', {'id': newRecordId()});
      expect(await tokens.read(), next);
    },
  );
  test(
    'Nutrition write stops before HTTP when the acting account changes',
    () async {
      final tokens = MemoryTokenStorage();
      await tokens.write(newRecordId());
      var sent = false;
      final repo = NutritionRepository(
        ApiClient(
          client: MockClient((_) async {
            sent = true;
            return http.Response('{}', 200);
          }),
          tokens: tokens,
          baseUrl: 'http://test',
        ),
        isCurrentAccount: () => false,
      );
      await expectLater(
        repo.write('POST', '/api/me/meals', {}),
        throwsA(isA<Exception>()),
      );
      expect(sent, isFalse);
    },
  );
  test('Unknown nutrition remains null and partial totals stay labelled', () {
    final value = NutrientTotal.fromJson({
      'value': null,
      'coverage': 'UNKNOWN',
      'knownItems': 0,
      'totalItems': 1,
    });
    expect(value.value, isNull);
    expect(value.label('kkal'), 'Belum tersedia');
    expect(
      NutrientTotal.fromJson({
        'value': 150,
        'coverage': 'PARTIAL',
        'knownItems': 1,
        'totalItems': 2,
      }).label('kkal'),
      contains('sebagian'),
    );
  });
  testWidgets('Meal form validates required items without submitting', (
    tester,
  ) async {
    await initializeDateFormatting('id_ID');
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const MealFormScreen())],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Simpan makanan'));
    await tester.tap(find.text('Simpan makanan'));
    await tester.pumpAndSettle();
    expect(find.text('Tambahkan setidaknya satu makanan.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
