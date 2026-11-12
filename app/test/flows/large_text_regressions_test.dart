import 'dart:convert';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/core/widgets/detail_kit.dart';
import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/auth/data/session_user.dart';
import 'package:app/features/community/data/community_repository.dart';
import 'package:app/features/community/presentation/community_widgets.dart';
import 'package:app/features/notifications/application/realtime_controller.dart';
import 'package:app/features/notifications/data/realtime_connector.dart';
import 'package:app/features/notifications/presentation/notifications_screen.dart';
import 'package:app/features/nutrition/data/nutrition_models.dart';
import 'package:app/features/nutrition/presentation/nutrition_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

class _Auth extends AuthController {
  @override
  AuthState build() => const AuthAuthenticated(
    SessionUser(id: 'a', email: 'a@x.test', name: 'A', emailVerified: true),
  );
}

Widget _scaled(Widget child, double scale) => MediaQuery(
  data: const MediaQueryData(
    size: Size(360, 800),
  ).copyWith(textScaler: TextScaler.linear(scale)),
  child: child,
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(720, 1600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets(
    'Inbox at 2x text: the live-connection status row wraps instead of overflowing',
    (tester) async {
      _phone(tester);
      final tokens = MemoryTokenStorage();
      await tokens.write('t');
      final api = ApiClient(
        tokens: tokens,
        baseUrl: 'http://test',
        client: MockClient(
          (r) async => http.Response(
            jsonEncode({'items': [], 'nextCursor': null, 'unread': 0}),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const NotificationsScreen()),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(_Auth.new),
            apiClientProvider.overrideWithValue(api),
            tokenStorageProvider.overrideWithValue(tokens),
            realtimeConnectorProvider.overrideWithValue(
              SilentRealtimeConnector(),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: const TextScaler.linear(2.0)),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final status = find.text('Menyambungkan pembaruan langsung…');
      expect(status, findsOneWidget);
      expect(tester.getRect(status).right, lessThanOrEqualTo(360));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Recognition badge at 2x text becomes a full-width row so the title is not split mid-word',
    (tester) async {
      _phone(tester);
      final badge = Recognition.fromJson({
        'key': 'CHALLENGE_JOINED_1',
        'category': 'CHALLENGE',
        'title': 'Tantangan pertama',
        'detail': 'Kamu ikut tantangan komunitas untuk pertama kali.',
        'achievedAt': '2026-11-10T03:00:00Z',
      });
      Future<void> render(double scale) => tester.pumpWidget(
        MaterialApp(
          home: _scaled(
            Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(children: [RecognitionBadge(recognition: badge)]),
              ),
            ),
            scale,
          ),
        ),
      );
      await render(1.0);
      expect(tester.getSize(find.byType(RecognitionBadge)).width, 120);
      await render(2.0);
      expect(
        tester.getSize(find.byType(RecognitionBadge)).width,
        greaterThan(300),
      );
      expect(
        find.descendant(
          of: find.byType(RecognitionBadge),
          matching: find.byType(Row),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Nutrition summary sits directly in the detail section: one title, label/value rows, no nested card',
    (tester) async {
      _phone(tester);
      const totals = {
        'calories': NutrientTotal(420, 'COMPLETE', 2, 2),
        'carbohydrates': NutrientTotal(55, 'PARTIAL', 1, 2),
      };
      await tester.pumpWidget(
        MaterialApp(
          home: _scaled(
            const Scaffold(
              body: SingleChildScrollView(
                child: DetailSection(
                  title: 'Ringkasan gizi',
                  children: [NutritionTotals(totals: totals)],
                ),
              ),
            ),
            2.0,
          ),
        ),
      );
      expect(
        find.textContaining(RegExp('ringkasan gizi', caseSensitive: false)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(NutritionTotals),
          matching: find.byType(Card),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(NutritionTotals),
          matching: find.byType(DetailRow),
        ),
        findsNWidgets(nutrientLabels.length),
      );
      expect(find.text('Belum tersedia'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
