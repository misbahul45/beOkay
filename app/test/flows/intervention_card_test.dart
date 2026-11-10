import 'dart:convert';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/features/interventions/application/intervention_controller.dart';
import 'package:app/features/interventions/data/intervention_repository.dart';
import 'package:app/features/interventions/presentation/intervention_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object b, [int s = 200]) => http.Response(
  jsonEncode(b),
  s,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _item({String id = 'i1'}) => {
  'id': id,
  'trigger': 'GOAL_WINDOW_APPROACHING',
  'content': {
    'title': 'Tujuanmu',
    'body': 'Jalan sore: mau catat check-in hari ini?',
    'action': 'OPEN_GOALS',
  },
};

Future<(Widget, List<http.Request>)> _app(
  http.Response Function(http.Request) h,
) async {
  final tokens = MemoryTokenStorage();
  await tokens.write('t');
  final seen = <http.Request>[];
  final repo = InterventionRepository(
    ApiClient(
      tokens: tokens,
      baseUrl: 'http://test',
      client: MockClient((r) async {
        seen.add(r);
        return h(r);
      }),
    ),
    isCurrentAccount: () => true,
  );
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: InterventionCard()),
      ),
      GoRoute(
        path: '/goals',
        builder: (_, _) => const Scaffold(body: Text('layar tujuan')),
      ),
    ],
  );
  return (
    ProviderScope(
      overrides: [interventionRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(routerConfig: router),
    ),
    seen,
  );
}

void main() {
  testWidgets(
    'Nothing is shown when the server has no suggestion, and failures never show an error',
    (tester) async {
      final (app, _) = await _app(
        (r) => r.url.path == '/api/me/interventions'
            ? _json({'items': <dynamic>[], 'consentRequired': false})
            : _json({}, 500),
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      expect(find.text('Tujuanmu'), findsNothing);
      final (broken, _) = await _app((r) => _json({}, 500));
      await tester.pumpWidget(broken);
      await tester.pumpAndSettle();
      expect(find.textContaining('Tujuanmu'), findsNothing);
      expect(find.textContaining('Terjadi kendala'), findsNothing);
    },
  );

  testWidgets(
    'Card shows one suggestion; "Nanti" snoozes 120 minutes and "Jangan lagi" stops that type, each as one request',
    (tester) async {
      var served = true;
      final (app, seen) = await _app((r) {
        if (r.url.path == '/api/me/interventions') {
          return _json({
            'items': served ? [_item()] : <dynamic>[],
            'consentRequired': false,
          });
        }
        if (r.url.path == '/api/me/interventions/evaluate') {
          return _json({'id': 'i1'}, 200);
        }
        if (r.url.path.endsWith('/response')) {
          served = false;
          return _json({'id': 'i1'});
        }
        return _json({}, 404);
      });
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      expect(find.text('Tujuanmu'), findsOneWidget);
      expect(find.textContaining('mau catat check-in'), findsOneWidget);
      await tester.tap(find.text('Nanti'));
      await tester.pumpAndSettle();
      final body =
          jsonDecode(
                seen.lastWhere((r) => r.url.path.endsWith('/response')).body,
              )
              as Map<String, dynamic>;
      expect(body, {'kind': 'NOT_NOW', 'snoozeMinutes': 120});
      expect(
        find.text('Tujuanmu'),
        findsNothing,
      ); // kartu hilang setelah ditanggapi
    },
  );

  testWidgets(
    '"Jangan lagi", "Terlalu sering" and the one-week pause each call the right endpoint',
    (tester) async {
      final kinds = <String>[];
      var paused = false;
      final (app, _) = await _app((r) {
        if (r.url.path == '/api/me/interventions') {
          return _json({
            'items': [_item()],
            'consentRequired': false,
          });
        }
        if (r.url.path.endsWith('/response')) {
          kinds.add((jsonDecode(r.body) as Map)['kind'] as String);
          return _json({});
        }
        if (r.url.path == '/api/me/intervention-preferences') {
          paused = (jsonDecode(r.body) as Map)['pauseForHours'] == 168;
          return _json({});
        }
        return _json({});
      });
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jangan lagi'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Terlalu sering'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jeda 1 minggu'));
      await tester.pumpAndSettle();
      expect(kinds, ['STOP_THIS_TYPE', 'TOO_FREQUENT']);
      expect(paused, isTrue);
    },
  );

  testWidgets(
    '"Buka" is recorded as OPENED (not as useful) and then opens the goals screen',
    (tester) async {
      String? kind;
      final (app, _) = await _app((r) {
        if (r.url.path == '/api/me/interventions') {
          return _json({
            'items': [_item()],
            'consentRequired': false,
          });
        }
        if (r.url.path.endsWith('/response')) {
          kind = (jsonDecode(r.body) as Map)['kind'] as String;
          return _json({});
        }
        return _json({});
      });
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Buka'));
      await tester.pumpAndSettle();
      expect(kind, 'OPENED');
      expect(find.text('layar tujuan'), findsOneWidget);
    },
  );

  testWidgets('A failed response keeps the card and says so briefly', (
    tester,
  ) async {
    final (app, _) = await _app((r) {
      if (r.url.path == '/api/me/interventions') {
        return _json({
          'items': [_item()],
          'consentRequired': false,
        });
      }
      if (r.url.path.endsWith('/response')) {
        return _json({
          'error': {'code': 'X', 'message': 'x'},
        }, 500);
      }
      return _json({});
    });
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nanti'));
    await tester.pumpAndSettle();
    expect(find.text('Belum bisa disimpan. Coba lagi.'), findsOneWidget);
    expect(find.text('Tujuanmu'), findsOneWidget);
  });
}
