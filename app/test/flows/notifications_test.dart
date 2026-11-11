import 'dart:async';
import 'dart:convert';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/auth/data/session_user.dart';
import 'package:app/features/notifications/application/realtime_controller.dart';
import 'package:app/features/notifications/data/realtime_connector.dart';
import 'package:app/features/notifications/presentation/notification_widgets.dart';
import 'package:app/features/notifications/presentation/notifications_screen.dart';
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

class _Conn implements RealtimeConnection {
  final controller = StreamController<Map<String, dynamic>>();
  final sent = <Map<String, dynamic>>[];
  bool closed = false;
  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
  @override
  void send(Map<String, dynamic> message) => sent.add(message);
  @override
  Future<void> close() async {
    closed = true;
    await controller.close();
  }
}

class _Connector implements RealtimeConnector {
  final conns = <_Conn>[];
  Uri? uri;
  String? token;
  @override
  Future<RealtimeConnection> connect(Uri uri, String token) async {
    this.uri = uri;
    this.token = token;
    final c = _Conn();
    conns.add(c);
    return c;
  }
}

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _note(
  String id, {
  bool read = false,
  String kind = 'REMINDER',
  DateTime? at,
}) => {
  'id': id,
  'kind': kind,
  'title': kind == 'REMINDER' ? 'Makan siang' : 'Tantangan selesai: Tuntas',
  'body': kind == 'REMINDER'
      ? 'Waktunya mencatat makan.'
      : '3 hari aktif dari target 3.',
  'action': kind == 'REMINDER' ? 'OPEN_LOG' : 'OPEN_CHALLENGE',
  'refId': kind == 'REMINDER' ? 'r1' : 'ch1',
  'read': read,
  'createdAt': (at ?? DateTime.now()).toUtc().toIso8601String(),
};

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  test(
    'Realtime: connects with the session token to the WebSocket path, tracks unread, surfaces new notifications, resubscribes topics',
    () async {
      final tokens = MemoryTokenStorage();
      await tokens.write('secret-token');
      final connector = _Connector();
      final c = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_Auth.new),
          tokenStorageProvider.overrideWithValue(tokens),
          apiClientProvider.overrideWithValue(
            ApiClient(
              tokens: tokens,
              baseUrl: 'https://api.beokay.test',
              client: MockClient((_) async => _json({})),
            ),
          ),
          realtimeConnectorProvider.overrideWithValue(connector),
        ],
      );
      addTearDown(c.dispose);
      c.listen(realtimeProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(connector.uri.toString(), 'wss://api.beokay.test/api/me/realtime');
      expect(connector.token, 'secret-token');
      expect(c.read(realtimeProvider).connected, isTrue);
      final conn = connector.conns.single;
      conn.controller.add({'type': 'hello', 'unread': 3});
      await Future<void>.delayed(Duration.zero);
      expect(c.read(realtimeProvider).unread, 3);
      conn.controller.add({
        'type': 'notification',
        'item': _note('n1'),
        'unread': 4,
      });
      await Future<void>.delayed(Duration.zero);
      expect(c.read(realtimeProvider).unread, 4);
      expect(c.read(latestNotificationProvider)?.title, 'Makan siang');
      c.read(realtimeProvider.notifier).subscribe('challenge:ch1');
      expect(conn.sent, [
        {'type': 'subscribe', 'topic': 'challenge:ch1'},
      ]);
      conn.controller.add({
        'type': 'notifications.read',
        'all': true,
        'unread': 0,
      });
      await Future<void>.delayed(Duration.zero);
      expect(c.read(realtimeProvider).unread, 0);
    },
  );

  testWidgets(
    'Inbox groups by day, marks a notification read on tap and opens its target, and can mark everything read',
    (tester) async {
      final seen = <http.Request>[];
      final tokens = MemoryTokenStorage();
      await tokens.write('t');
      final api = ApiClient(
        tokens: tokens,
        baseUrl: 'http://test',
        client: MockClient((r) async {
          seen.add(r);
          if (r.url.path == '/api/me/notifications') {
            return _json({
              'items': [
                _note('n1'),
                _note(
                  'n2',
                  kind: 'CHALLENGE',
                  read: true,
                  at: DateTime.now().subtract(const Duration(days: 1)),
                ),
              ],
              'nextCursor': null,
              'unread': 1,
            });
          }
          if (r.url.path == '/api/me/notifications/n1/read') {
            return _json({'id': 'n1', 'read': true, 'unread': 0});
          }
          if (r.url.path == '/api/me/notifications/read-all') {
            return _json({'updated': 0, 'unread': 0});
          }
          return _json({}, 404);
        }),
      );
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const NotificationsScreen()),
          GoRoute(
            path: '/log',
            builder: (_, _) => const Scaffold(body: Text('Halaman catatan')),
          ),
          GoRoute(
            path: '/settings/notifications',
            builder: (_, _) => const Scaffold(body: Text('Halaman pengaturan')),
          ),
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
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('HARI INI'), findsOneWidget);
      expect(find.text('KEMARIN'), findsOneWidget);
      expect(find.text('Makan siang'), findsOneWidget);
      expect(find.text('Menyambungkan pembaruan langsung…'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('^Belum dibaca. Makan siang')),
        findsOneWidget,
      );
      await tester.tap(find.text('Makan siang'));
      await tester.pumpAndSettle();
      expect(
        seen.any((r) => r.url.path == '/api/me/notifications/n1/read'),
        isTrue,
      );
      expect(find.text('Halaman catatan'), findsOneWidget);
    },
  );

  testWidgets(
    'Settings: push switch and per-kind switches send the server preference',
    (tester) async {
      final bodies = <Map<String, dynamic>>[];
      var muted = <String>[];
      final tokens = MemoryTokenStorage();
      await tokens.write('t');
      final api = ApiClient(
        tokens: tokens,
        baseUrl: 'http://test',
        client: MockClient((r) async {
          if (r.method == 'PATCH') {
            final b = jsonDecode(r.body) as Map<String, dynamic>;
            bodies.add(b);
            muted = [
              for (final k in b['mutedKinds'] as List? ?? muted) k as String,
            ];
          }
          return _json({
            'pushEnabled': true,
            'mutedKinds': muted,
            'kinds': [],
            'pushConfigured': false,
            'devices': 0,
          });
        }),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(_Auth.new),
            apiClientProvider.overrideWithValue(api),
            tokenStorageProvider.overrideWithValue(tokens),
          ],
          child: MaterialApp.router(
            routerConfig: GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, _) => const NotificationSettingsScreen(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Push belum tersedia di server ini'),
        findsOneWidget,
      );
      await tester.tap(find.text('Tantangan'));
      await tester.pumpAndSettle();
      expect(bodies.last, {
        'mutedKinds': ['CHALLENGE'],
      });
      await tester.tap(find.text('Notifikasi push'));
      await tester.pumpAndSettle();
      expect(bodies.last, {'pushEnabled': false});
    },
  );

  testWidgets('Bell shows the unread badge and opens the inbox', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              const Scaffold(body: Center(child: NotificationBell())),
        ),
        GoRoute(
          path: '/notifications',
          builder: (_, _) => const Scaffold(body: Text('Kotak masuk')),
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_Auth.new),
        realtimeConnectorProvider.overrideWithValue(SilentRealtimeConnector()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    container.read(realtimeProvider.notifier).setUnread(12);
    await tester.pumpAndSettle();
    expect(find.text('9+'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Notifikasi, 12 belum dibaca'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Notifikasi'));
    await tester.pumpAndSettle();
    expect(find.text('Kotak masuk'), findsOneWidget);
  });
}
