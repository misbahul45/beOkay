import 'dart:convert';

import 'package:app/core/network/account_scoped_repository.dart';
import 'package:app/core/network/api_client.dart';
import 'package:app/core/offline/offline_queue.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/features/glucose/data/glucose_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _glucose(String id) => {
  'id': id,
  'originalValue': 110,
  'originalUnit': 'mg/dL',
  'measuredAt': '2026-11-09T01:00:00.000Z',
};

Future<GlucoseRepository> _repo(
  MemoryKeyValueStore store,
  String account, {
  required bool online,
  void Function(String body)? onRequest,
}) async {
  final tokens = MemoryTokenStorage();
  await tokens.write('token-$account');
  final queue = OfflineQueue(store, account);
  return GlucoseRepository(
    ApiClient(
      tokens: tokens,
      baseUrl: 'http://test',
      client: MockClient((request) async {
        onRequest?.call(request.body);
        if (!online) throw http.ClientException('no route');
        return http.Response('{}', 200);
      }),
    ),
    isCurrentAccount: () => true,
    enqueueOffline: queue.add,
  );
}

void main() {
  test(
    'A create that fails on the network is queued and reported as QueuedOffline',
    () async {
      final store = MemoryKeyValueStore();
      final repo = await _repo(store, 'a', online: false);
      await expectLater(
        repo.save(_glucose('r1')),
        throwsA(isA<QueuedOffline>()),
      );
      final ops = await OfflineQueue(store, 'a').load();
      expect(ops, hasLength(1));
      expect(ops.single.domain, 'glucose');
      expect(ops.single.recordId, 'r1');
      expect(ops.single.operationType, 'create');
      expect(ops.single.state, QueueState.savedLocal);
      expect(
        ops.single.payload.containsKey('id'),
        isFalse,
      ); // id travels as recordId
      expect(ops.single.toWire()['recordId'], 'r1');
    },
  );

  test(
    'Retrying the same record does not duplicate the queued operation',
    () async {
      final store = MemoryKeyValueStore();
      final repo = await _repo(store, 'a', online: false);
      for (var i = 0; i < 3; i++) {
        await expectLater(
          repo.save(_glucose('r1')),
          throwsA(isA<QueuedOffline>()),
        );
      }
      expect(await OfflineQueue(store, 'a').load(), hasLength(1));
    },
  );

  test(
    'Queues are isolated per account and never rebound to another account',
    () async {
      final store = MemoryKeyValueStore();
      await expectLater(
        (await _repo(store, 'a', online: false)).save(_glucose('r1')),
        throwsA(isA<QueuedOffline>()),
      );
      expect(await OfflineQueue(store, 'b').load(), isEmpty);
      expect(store.data.keys.single, 'beokay.queue.a');
      await OfflineQueue(
        store,
        'b',
      ).clear(); // clearing another account's queue leaves A intact
      expect(await OfflineQueue(store, 'a').load(), hasLength(1));
    },
  );

  test(
    'A correction that fails on the network is queued as an update with its version and reason',
    () async {
      final store = MemoryKeyValueStore();
      final repo = await _repo(store, 'a', online: false);
      await expectLater(
        repo.save({
          'originalValue': 120,
          'expectedVersion': 3,
          'reason': 'koreksi',
        }, id: 'r1'),
        throwsA(isA<QueuedOffline>()),
      );
      final op = (await OfflineQueue(store, 'a').load()).single;
      expect(op.operationType, 'update');
      expect(op.isCorrection, isTrue);
      expect(op.recordId, 'r1');
      expect(op.payload['expectedVersion'], 3);
      expect(op.payload['reason'], 'koreksi');
      expect(op.toWire()['operationType'], 'update');
    },
  );

  test(
    'Two pending corrections to one record merge: newest values win, first expectedVersion is kept',
    () async {
      final store = MemoryKeyValueStore();
      final repo = await _repo(store, 'a', online: false);
      await expectLater(
        repo.save({
          'originalValue': 120,
          'expectedVersion': 3,
          'reason': 'pertama',
        }, id: 'r1'),
        throwsA(isA<QueuedOffline>()),
      );
      await expectLater(
        repo.save({
          'originalValue': 130,
          'expectedVersion': 3,
          'reason': 'kedua',
        }, id: 'r1'),
        throwsA(isA<QueuedOffline>()),
      );
      final ops = await OfflineQueue(store, 'a').load();
      expect(ops, hasLength(1));
      expect(ops.single.payload['originalValue'], 130);
      expect(ops.single.payload['reason'], 'kedua');
      expect(ops.single.payload['expectedVersion'], 3);
    },
  );

  test(
    'A correction and a create for different records stay separate',
    () async {
      final store = MemoryKeyValueStore();
      final repo = await _repo(store, 'a', online: false);
      await expectLater(
        repo.save(_glucose('new1')),
        throwsA(isA<QueuedOffline>()),
      );
      await expectLater(
        repo.save({
          'originalValue': 120,
          'expectedVersion': 1,
          'reason': 'x',
        }, id: 'old1'),
        throwsA(isA<QueuedOffline>()),
      );
      expect(
        (await OfflineQueue(store, 'a').load()).map((o) => o.operationType),
        ['create', 'update'],
      );
    },
  );

  test('Online writes bypass the queue and send the id in the body', () async {
    final store = MemoryKeyValueStore();
    String? sent;
    final repo = await _repo(
      store,
      'a',
      online: true,
      onRequest: (b) => sent = b,
    );
    try {
      await repo.save(_glucose('r9'));
    } catch (_) {
      // Fake body is empty; only the request matters here.
    }
    expect(jsonDecode(sent!)['id'], 'r9');
    expect(await OfflineQueue(store, 'a').load(), isEmpty);
  });

  test('Queue survives restart and ignores corrupt storage', () async {
    final store = MemoryKeyValueStore();
    await OfflineQueue(store, 'a').add(
      QueuedOperation(
        operationId: 'o1',
        domain: 'goal_checkin',
        recordId: 'c1',
        parentId: 'g1',
        operationType: 'create',
        payload: const {'status': 'completed'},
        createdAt: DateTime.utc(2026, 11, 9),
        state: QueueState.conflict,
        errorCode: 'VERSION_CONFLICT',
      ),
    );
    final again = await OfflineQueue(store, 'a').load();
    expect(again.single.parentId, 'g1');
    expect(again.single.state, QueueState.conflict);
    store.data['beokay.queue.a'] = 'not json';
    expect(await OfflineQueue(store, 'a').load(), isEmpty);
  });
}
