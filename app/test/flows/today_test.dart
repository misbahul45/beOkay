import 'package:app/core/network/api_exception.dart';
import 'package:app/features/today/application/today_controller.dart';
import 'package:app/features/today/data/today_overview.dart';
import 'package:app/features/today/presentation/today_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:go_router/go_router.dart';

TodayOverview overview() => TodayOverview.fromJson({
  'displayName': 'Rina',
  'date': '2026-11-09',
  'greeting': 'Selamat pagi',
  'timezone': 'Asia/Jakarta',
  'glucoseUnit': 'mmol/L',
  'generatedAt': '2026-11-09T02:00:00Z',
  'metrics': [
    for (final domain in ['glucose', 'nutrition', 'activity', 'medication'])
      {'domain': domain, 'availability': 'NOT_IMPLEMENTED', 'value': null},
  ],
});

void main() {
  testWidgets('Today preview opens the original glucose observation', (
    tester,
  ) async {
    await initializeDateFormatting('id_ID');
    final today = TodayOverview.fromJson({
      'date': '2026-11-08',
      'greeting': 'Selamat pagi',
      'timezone': 'Asia/Jakarta',
      'glucoseUnit': 'mmol/L',
      'generatedAt': '2026-11-08T00:00:00Z',
      'timeline': {
        'items': [
          {
            'domain': 'glucose',
            'recordId': 'original-record',
            'localDate': '2026-11-08',
            'localTime': '07:00',
            'displayValue': 5.5,
            'displayUnit': 'mmol/L',
            'qualityStatus': 'user_reported',
          },
        ],
      },
    });
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: SingleChildScrollView(child: TodaySection()),
          ),
        ),
        GoRoute(
          path: '/glucose/original-record',
          builder: (_, _) =>
              const Scaffold(body: Text('Original observation destination')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [todayProvider.overrideWith((ref) async => today)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Glukosa · 07:00'));
    await tester.tap(find.text('Glukosa · 07:00'));
    await tester.pumpAndSettle();
    expect(find.text('Original observation destination'), findsOneWidget);
  });
  testWidgets(
    'Today displays unavailable domains honestly at narrow width and large text',
    (tester) async {
      await initializeDateFormatting('id_ID');
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [todayProvider.overrideWith((ref) async => overview())],
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: SingleChildScrollView(child: TodaySection()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Selamat pagi'), findsOneWidget);
      expect(find.textContaining('9 November 2026'), findsOneWidget);
      expect(find.text('Belum tersedia'), findsNWidgets(3));
      expect(find.text('Belum ada pengukuran hari ini.'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Today connection failure offers retry and hides previous metrics',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            todayProvider.overrideWith((ref) async {
              attempts++;
              throw const ApiException(
                status: 0,
                code: ApiException.networkCode,
                message: 'Tidak bisa terhubung.',
              );
            }),
          ],
          child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: TodaySection())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Glukosa'), findsNothing);
      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
    },
  );
}
