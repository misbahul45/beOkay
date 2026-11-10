import 'dart:async';
import 'dart:convert';

import 'package:app/core/notifications/reminder_scheduler.dart';
import 'package:app/core/offline/offline_queue.dart';
import 'package:app/core/offline/sync_controller.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/auth/data/session_user.dart';
import 'package:app/features/push/application/push_controller.dart';
import 'package:app/features/push/data/push_client.dart';
import 'package:app/features/reminders/application/reminders_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fake_scheduler.dart';

class _Auth extends AuthController {
  @override
  AuthState build() => const AuthAuthenticated(
    SessionUser(id: 'acc1', email: 'a@x.test', name: 'A', emailVerified: true),
  );
}

class _FakePush implements PushClient {
  _FakePush({this.isAvailable = true, this.permission = true})
    : tokenValue = 'tkn-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  bool isAvailable, permission;
  String? tokenValue;
  int deleted = 0;
  final refresh = StreamController<String>.broadcast();
  @override
  Future<bool> available() async => isAvailable;
  @override
  Future<bool> requestPermission() async => permission;
  @override
  Future<String?> token() async => tokenValue;
  @override
  Stream<String> get onTokenRefresh => refresh.stream;
  @override
  Future<void> deleteToken() async => deleted++;
}

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Future<
  (
    ProviderContainer,
    _FakePush,
    MemoryKeyValueStore,
    FakeReminderScheduler,
    List<http.Request>,
  )
>
_setup({_FakePush? push}) async {
  final tokens = MemoryTokenStorage();
  await tokens.write('t');
  final p = push ?? _FakePush();
  final store = MemoryKeyValueStore();
  final sched = FakeReminderScheduler();
  final seen = <http.Request>[];
  final c = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith(_Auth.new),
      tokenStorageProvider.overrideWithValue(tokens),
      pushClientProvider.overrideWithValue(p),
      keyValueStoreProvider.overrideWithValue(store),
      reminderSchedulerProvider.overrideWithValue(sched),
      httpClientProvider.overrideWithValue(
        MockClient((r) async {
          seen.add(r);
          if (r.url.path == '/api/me/push-devices' && r.method == 'POST') {
            return _json({'id': 'dev1', 'tokenHint': '…abcdef'}, 201);
          }
          if (r.url.path.startsWith('/api/me/push-devices/') &&
              r.method == 'DELETE') {
            return _json({'removed': true});
          }
          if (r.url.path == '/api/me/reminders/upcoming') {
            return _json({
              'items': [
                {
                  'at': DateTime.now()
                      .toUtc()
                      .add(const Duration(days: 1))
                      .toIso8601String(),
                  'title': 'Pengingat beOkay',
                  'body': 'Buka beOkay untuk mencatat.',
                },
              ],
            });
          }
          return _json({}, 404);
        }),
      ),
    ],
  );
  addTearDown(c.dispose);
  return (c, p, store, sched, seen);
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 80));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // penjadwal pengingat memakai WidgetsBinding
  test(
    'Without Firebase configuration push is "unavailable" and nothing is requested',
    () async {
      final (c, push, _, _, seen) = await _setup(
        push: _FakePush(isAvailable: false),
      );
      c.listen(pushControllerProvider, (_, _) {});
      await _settle();
      expect(c.read(pushControllerProvider).status, PushStatus.unavailable);
      await c.read(pushControllerProvider.notifier).enable();
      expect(c.read(pushControllerProvider).status, PushStatus.unavailable);
      expect(seen, isEmpty);
      expect(push.deleted, 0);
    },
  );

  test(
    'Enabling asks permission, registers the token with the server, and remembers the device id',
    () async {
      final (c, _, store, _, seen) = await _setup();
      c.listen(pushControllerProvider, (_, _) {});
      await _settle();
      expect(c.read(pushControllerProvider).status, PushStatus.off);
      await c.read(pushControllerProvider.notifier).enable();
      expect(c.read(pushControllerProvider).status, PushStatus.on);
      final post = seen.firstWhere((r) => r.method == 'POST');
      final body = jsonDecode(post.body) as Map<String, dynamic>;
      expect(body['token'], startsWith('tkn-'));
      expect(body['platform'], anyOf('android', 'ios'));
      expect(await store.read('beokay.push.acc1'), 'dev1');
    },
  );

  test(
    'Denied permission or missing token leaves push off with a readable message and no server call',
    () async {
      final (c, _, _, _, seen) = await _setup(
        push: _FakePush(permission: false),
      );
      c.listen(pushControllerProvider, (_, _) {});
      await _settle();
      await c.read(pushControllerProvider.notifier).enable();
      expect(c.read(pushControllerProvider).status, PushStatus.off);
      expect(
        c.read(pushControllerProvider).message,
        contains('belum diizinkan'),
      );
      expect(seen.where((r) => r.method == 'POST'), isEmpty);

      final (c2, p2, _, _, seen2) = await _setup();
      p2.tokenValue = null;
      c2.listen(pushControllerProvider, (_, _) {});
      await _settle();
      await c2.read(pushControllerProvider.notifier).enable();
      expect(
        c2.read(pushControllerProvider).message,
        contains('Token notifikasi'),
      );
      expect(seen2.where((r) => r.method == 'POST'), isEmpty);
    },
  );

  test(
    'Disabling removes the device on the server, revokes the device token, and clears the local flag',
    () async {
      final (c, push, store, _, seen) = await _setup();
      c.listen(pushControllerProvider, (_, _) {});
      await _settle();
      await c.read(pushControllerProvider.notifier).enable();
      await c.read(pushControllerProvider.notifier).disable();
      expect(
        seen.where(
          (r) =>
              r.method == 'DELETE' && r.url.path == '/api/me/push-devices/dev1',
        ),
        hasLength(1),
      );
      expect(push.deleted, 1);
      expect(await store.read('beokay.push.acc1'), isNull);
      expect(c.read(pushControllerProvider).status, PushStatus.off);
    },
  );

  test('A refreshed token is registered again while push is on', () async {
    final (c, push, _, _, seen) = await _setup();
    c.listen(pushControllerProvider, (_, _) {});
    await _settle();
    await c.read(pushControllerProvider.notifier).enable();
    push.refresh.add('tkn-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
    await _settle();
    final posts = seen.where((r) => r.method == 'POST').toList();
    expect(posts, hasLength(2));
    expect(jsonDecode(posts.last.body)['token'], startsWith('tkn-bbbb'));
  });

  test(
    'With push on, local reminder notifications are cleared (no duplicates); with push off they are scheduled',
    () async {
      final (c, _, store, sched, seen) = await _setup();
      c.listen(pushControllerProvider, (_, _) {});
      c.listen(reminderSyncProvider, (_, _) {});
      await _settle();
      expect(sched.scheduled, hasLength(1)); // push mati: jadwal lokal

      await store.write('beokay.push.acc1', 'dev1');
      await c.read(reminderSyncProvider.notifier).sync();
      expect(sched.scheduled, isEmpty); // push aktif: lokal dikosongkan
      expect(sched.cancelCount, greaterThan(0));
    },
  );
}
