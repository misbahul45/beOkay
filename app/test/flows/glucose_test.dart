import 'package:app/features/glucose/data/glucose_models.dart';
import 'package:app/features/glucose/presentation/glucose_form_screen.dart';
import 'package:app/core/widgets/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:app/core/network/api_client.dart';
import 'package:app/core/network/api_exception.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/core/ids/record_id.dart';
import 'package:app/features/glucose/data/glucose_repository.dart';
import 'package:app/features/glucose/application/glucose_controller.dart';
import 'package:app/features/glucose/presentation/glucose_history_screen.dart';
import 'package:app/features/glucose/presentation/glucose_chart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

void main() {
  for (final status in [400, 409, 503]) {
    testWidgets(
      'Glucose correction handles HTTP $status without unsafe overwrite',
      (tester) async {
        await initializeDateFormatting('id_ID');
        final tokens = MemoryTokenStorage();
        await tokens.write(newRecordId());
        final payloads = <String>[];
        final repo = GlucoseRepository(
          ApiClient(
            tokens: tokens,
            baseUrl: 'http://test',
            client: MockClient((request) async {
              payloads.add(request.body);
              return http.Response(
                jsonEncode({
                  'error': {
                    'code': status == 409
                        ? 'VERSION_CONFLICT'
                        : 'VALIDATION_ERROR',
                    'message': 'Synthetic error',
                  },
                }),
                status,
              );
            }),
          ),
          isCurrentAccount: () => true,
        );
        final record = GlucoseRecord.fromJson({
          'id': newRecordId(),
          'originalValue': 5.5,
          'originalUnit': 'mmol/L',
          'displayValue': 99,
          'displayUnit': 'mg/dL',
          'valueMgDl': 99.088,
          'measuredAt': DateTime.now()
              .subtract(const Duration(hours: 1))
              .toUtc()
              .toIso8601String(),
          'localDate': '2026-11-08',
          'localTime': '12:00',
          'timezone': 'Asia/Jakarta',
          'version': 1,
          'mealContext': 'unknown',
          'qualityStatus': 'user_reported',
        });
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => GlucoseFormScreen(initial: record),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [glucoseRepositoryProvider.overrideWithValue(repo)],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        Finder field(String label) => find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is AppTextField && w.label == label,
          ),
          matching: find.byType(TextFormField),
        );
        await tester.ensureVisible(field('Alasan koreksi'));
        await tester.enterText(field('Alasan koreksi'), 'Synthetic correction');
        await tester.ensureVisible(find.text('Simpan koreksi'));
        await tester.tap(find.text('Simpan koreksi'));
        await tester.pumpAndSettle();
        expect(payloads, hasLength(1));
        expect(
          tester.widget<TextFormField>(field('Nilai pengukuran')).enabled,
          status == 400,
        );
        if (status == 409) {
          expect(find.text('Muat ulang catatan'), findsOneWidget);
        }
        if (status == 503) {
          await tester.ensureVisible(find.text('Simpan koreksi'));
          await tester.tap(find.text('Simpan koreksi'));
          await tester.pumpAndSettle();
          expect(payloads, hasLength(2));
          expect(payloads.last, payloads.first);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  test(
    'Glucose writes capture session and reject account changes before HTTP',
    () async {
      final tokens = MemoryTokenStorage();
      final acting = newRecordId();
      await tokens.write(acting);
      var current = true;
      var calls = 0;
      final repo = GlucoseRepository(
        ApiClient(
          tokens: tokens,
          baseUrl: 'http://test',
          client: MockClient((request) async {
            calls++;
            expect(request.headers['Authorization'], 'Bearer $acting');
            await tokens.write(newRecordId());
            return http.Response('{}', 200);
          }),
        ),
        isCurrentAccount: () => current,
      );
      await repo.write('POST', '/api/me/glucose', {});
      current = false;
      await expectLater(
        repo.write('POST', '/api/me/glucose', {}),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 1);
    },
  );
  testWidgets(
    'Empty glucose history offers recording and returns to Today from root',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/glucose',
        routes: [
          GoRoute(
            path: '/glucose',
            builder: (_, _) => const GlucoseHistoryScreen(),
          ),
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
            glucosePageProvider.overrideWith(
              (ref, q) async =>
                  const GlucosePage([], null, 'Asia/Jakarta', 'mg/dL'),
            ),
            glucoseDayProvider.overrideWith(
              (ref, date) async => GlucoseDay.fromJson({
                'count': 0,
                'reviewCount': 0,
                'eligibleCount': 0,
                'displayUnit': 'mg/dL',
                'computationVersion': 'test',
                'computedAt': '2026-11-08T00:00:00Z',
              }),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Belum ada pengukuran'), findsOneWidget);
      expect(find.textContaining('Rata-rata belum tersedia'), findsOneWidget);
      await tester.tap(find.byTooltip('Kembali'));
      await tester.pumpAndSettle();
      expect(find.text('Today destination'), findsOneWidget);
    },
  );
  testWidgets('Glucose chart remains readable at narrow width and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final record = GlucoseRecord.fromJson({
      'id': 'test',
      'originalValue': 5.5,
      'originalUnit': 'mmol/L',
      'displayValue': 99,
      'displayUnit': 'mg/dL',
      'valueMgDl': 99.088,
      'measuredAt': '2026-11-08T00:00:00Z',
      'localDate': '2026-11-08',
      'localTime': '07:00',
      'timezone': 'Asia/Jakarta',
      'version': 1,
      'mealContext': 'unknown',
      'qualityStatus': 'needs_review',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: GlucoseChart(items: [record], unit: 'mg/dL'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Titik terpisah'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test(
    'Glucose input guard uses the selected source unit and preserves unknowns',
    () {
      expect(validateGlucoseInput('5.5', 'mmol/L'), isNull);
      for (final value in ['0', '-1', 'NaN', 'Infinity', '2001', '1.12345']) {
        expect(validateGlucoseInput(value, 'mg/dL'), isNotNull);
      }
      expect(validateGlucoseInput('200', 'mmol/L'), isNotNull);
      expect(validateGlucoseInput('5,5', 'mmol/L'), isNull);
    },
  );
  testWidgets(
    'Editing a converted observation preserves original value and unit',
    (tester) async {
      await initializeDateFormatting('id_ID');
      final record = GlucoseRecord.fromJson({
        'id': 'fixture',
        'originalValue': 5.5,
        'originalUnit': 'mmol/L',
        'displayValue': 99,
        'displayUnit': 'mg/dL',
        'valueMgDl': 99.088,
        'measuredAt': DateTime.now()
            .subtract(const Duration(hours: 1))
            .toUtc()
            .toIso8601String(),
        'localDate': '2026-11-08',
        'localTime': '12:00',
        'timezone': 'Asia/Jakarta',
        'version': 1,
        'mealContext': 'after_meal',
        'qualityStatus': 'user_reported',
        'source': 'manual_glucometer',
        'measurementType': 'capillary_blood',
      });
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => GlucoseFormScreen(initial: record),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await tester.pumpAndSettle();
      final input = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is AppTextField && w.label == 'Nilai pengukuran',
        ),
        matching: find.byType(TextFormField),
      );
      expect(tester.widget<TextFormField>(input).controller!.text, '5.5');
      expect(find.text('mmol/L'), findsOneWidget);
      await tester.enterText(input, '0');
      await tester.ensureVisible(find.text('Simpan koreksi'));
      await tester.tap(find.text('Simpan koreksi'));
      await tester.pumpAndSettle();
      expect(
        find.text('Masukkan nilai valid dalam batas numerik aplikasi.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
