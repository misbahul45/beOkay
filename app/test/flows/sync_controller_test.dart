import 'dart:convert';

import 'package:app/core/offline/offline_queue.dart';
import 'package:app/core/offline/sync_controller.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/auth/data/session_user.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Auth extends AuthController {
  @override
  AuthState build() => const AuthAuthenticated(SessionUser(id: 'a', email: 'a@x.test', name: 'A', emailVerified: true));
}

QueuedOperation _op(String id, {String domain = 'glucose'}) => QueuedOperation(
  operationId: 'op-$id',
  domain: domain,
  recordId: 'rec-$id',
  operationType: 'create',
  payload: const {'originalValue': 100},
  createdAt: DateTime.utc(2026, 11, 9),
);

Future<(ProviderContainer, MemoryKeyValueStore, List<String>)> _setup(http.Response Function(http.Request) handler) async {
  final store = MemoryKeyValueStore();
  final tokens = MemoryTokenStorage();
  await tokens.write('tok');
  final bodies = <String>[];
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith(_Auth.new),
      keyValueStoreProvider.overrideWithValue(store),
      tokenStorageProvider.overrideWithValue(tokens),
      httpClientProvider.overrideWithValue(MockClient((r) async {
        bodies.add(r.body);
        return handler(r);
      })),
    ],
  );
  addTearDown(container.dispose);
  return (container, store, bodies);
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  test('flush removes SYNCED, keeps CONFLICT and NEEDS_REVIEW with the reason', () async {
    final (c, store, bodies) = await _setup((r) {
      final ops = (jsonDecode(r.body)['operations'] as List).cast<Map>();
      return _json({
        'items': [
          {'operationId': ops[0]['operationId'], 'status': 'SYNCED', 'recordId': ops[0]['recordId']},
          {'operationId': ops[1]['operationId'], 'status': 'CONFLICT', 'recordId': ops[1]['recordId'], 'error': {'code': 'VERSION_CONFLICT', 'message': 'Data berubah'}},
          {'operationId': ops[2]['operationId'], 'status': 'NEEDS_REVIEW', 'recordId': ops[2]['recordId'], 'error': {'code': 'VALIDATION_ERROR', 'message': 'Tidak valid'}},
        ],
      });
    });
    final q = OfflineQueue(store, 'a');
    for (final i in ['1', '2', '3']) {
      await q.add(_op(i));
    }
    c.listen(syncControllerProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 50)); // build() auto-flush
    await c.read(syncControllerProvider.notifier).flush();
    final left = await q.load();
    expect(left.map((o) => (o.operationId, o.state)), [('op-2', QueueState.conflict), ('op-3', QueueState.needsReview)]);
    expect(left.first.errorCode, 'VERSION_CONFLICT');
    expect(c.read(syncControllerProvider).needsAttention, 2);
    expect(bodies, isNotEmpty);
    expect(jsonDecode(bodies.first)['operations'][0].containsKey('state'), isFalse); // wire format has no local state
  });

  test('a network failure keeps everything queued and flags offline', () async {
    final store = MemoryKeyValueStore();
    final tokens = MemoryTokenStorage();
    await tokens.write('tok');
    final c = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(_Auth.new),
      keyValueStoreProvider.overrideWithValue(store),
      tokenStorageProvider.overrideWithValue(tokens),
      httpClientProvider.overrideWithValue(MockClient((_) async => throw http.ClientException('down'))),
    ]);
    addTearDown(c.dispose);
    await OfflineQueue(store, 'a').add(_op('1'));
    c.listen(syncControllerProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await c.read(syncControllerProvider.notifier).flush();
    expect(c.read(syncControllerProvider).offline, isTrue);
    expect(await OfflineQueue(store, 'a').load(), hasLength(1));
  });

  test('consent withdrawal stops sending and clears unsent local data', () async {
    final (c, store, _) = await _setup((_) => _json({'error': {'code': 'CONSENT_REQUIRED', 'message': 'x'}}, 403));
    await OfflineQueue(store, 'a').add(_op('1'));
    c.listen(syncControllerProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await c.read(syncControllerProvider.notifier).flush();
    expect(c.read(syncControllerProvider).blockedByConsent, isTrue);
    await c.read(syncControllerProvider.notifier).clearForConsentWithdrawal();
    expect(await OfflineQueue(store, 'a').load(), isEmpty);
    expect(store.data, isEmpty);
  });

  test('discard removes only the chosen operation', () async {
    final (c, store, _) = await _setup((_) => _json({'items': []}));
    final q = OfflineQueue(store, 'a');
    await q.add(_op('1').copyWith(state: QueueState.conflict));
    await q.add(_op('2').copyWith(state: QueueState.conflict));
    c.listen(syncControllerProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await c.read(syncControllerProvider.notifier).discard('op-1');
    expect((await q.load()).single.operationId, 'op-2');
  });
}
