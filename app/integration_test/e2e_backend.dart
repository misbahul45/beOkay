import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../test/support/fake_backend.dart';

class E2EBackend {
  E2EBackend() {
    client = MockClient(_handle);
  }

  final identity = FakeBackend();
  late final MockClient client;
  bool offline = false;
  final glucose = <Map<String, dynamic>>[];
  final syncBatches = <List<dynamic>>[];
  final readIds = <String>[];
  final notifications = <Map<String, dynamic>>[
    {
      'id': 'n1',
      'kind': 'REFLECTION',
      'title': 'Refleksi mingguan siap',
      'body': 'Lihat yang sudah berjalan dan atur langkah minggu depan.',
      'action': 'OPEN_REFLECTION',
      'refId': null,
      'read': false,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    },
  ];

  http.Response _json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  String get _today {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> _record(Map<String, dynamic> b, String id) {
    final v = b['originalValue'] as num;
    final at = DateTime.parse(b['measuredAt'] as String).toLocal();
    return {
      'id': id,
      'originalValue': v,
      'originalUnit': b['originalUnit'],
      'displayValue': v,
      'displayUnit': 'mg/dL',
      'valueMgDl': v,
      'measuredAt': b['measuredAt'],
      'localDate': _today,
      'localTime':
          '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
      'timezone': 'Asia/Jakarta',
      'version': 1,
      'mealContext': b['mealContext'] ?? 'unknown',
      'qualityStatus': b['qualityStatus'] ?? 'user_reported',
      'notes': b['notes'],
      'archivedAt': null,
      'recordedAt': b['measuredAt'],
      'receivedAt': DateTime.now().toUtc().toIso8601String(),
      'alert': null,
    };
  }

  Future<http.Response> _handle(http.Request r) async {
    final path = r.url.path;
    final key = '${r.method} $path';
    final domain =
        path.startsWith('/api/me/') &&
        !path.startsWith('/api/me/consents') &&
        !path.startsWith('/api/me/onboarding') &&
        !path.startsWith('/api/me/profile') &&
        !path.startsWith('/api/me/health-profile') &&
        !path.startsWith('/api/me/preferences') &&
        !path.startsWith('/api/me/account');
    if (domain && offline) throw http.ClientException('offline');
    switch (key) {
      case 'GET /api/me/today':
        return _json({
          'date': _today,
          'greeting': 'Halo',
          'timezone': 'Asia/Jakarta',
          'glucoseUnit': 'mg/dL',
          'generatedAt': DateTime.now().toUtc().toIso8601String(),
          'events': <dynamic>[],
        });
      case 'POST /api/me/glucose':
        final b = jsonDecode(r.body) as Map<String, dynamic>;
        final rec = _record(b, b['id'] as String);
        glucose.add(rec);
        return _json(rec, 201);
      case 'POST /api/me/sync/operations':
        final ops = (jsonDecode(r.body) as Map)['operations'] as List;
        syncBatches.add(ops);
        for (final o in ops) {
          if ((o as Map)['domain'] == 'glucose') {
            glucose.add(
              _record(
                (o['payload'] as Map).cast<String, dynamic>(),
                o['recordId'] as String,
              ),
            );
          }
        }
        return _json({
          'items': [
            for (final o in ops)
              {
                'operationId': (o as Map)['operationId'],
                'status': 'SYNCED',
                'recordId': o['recordId'],
              },
          ],
        });
      case 'GET /api/me/notifications':
        return _json({
          'items': notifications,
          'nextCursor': null,
          'unread': notifications.where((n) => n['read'] != true).length,
        });
      case 'POST /api/me/notifications/read-all':
        for (final n in notifications) {
          n['read'] = true;
        }
        return _json({'updated': notifications.length, 'unread': 0});
    }
    if (r.method == 'POST' &&
        path.startsWith('/api/me/notifications/') &&
        path.endsWith('/read')) {
      final id = path.split('/')[4];
      readIds.add(id);
      for (final n in notifications) {
        if (n['id'] == id) n['read'] = true;
      }
      return _json({
        'id': id,
        'read': true,
        'unread': notifications.where((n) => n['read'] != true).length,
      });
    }
    if (r.method == 'GET' &&
        path.startsWith('/api/me/glucose/') &&
        path.split('/').length == 5) {
      final id = path.split('/')[4];
      final rec = glucose.where((g) => g['id'] == id).toList();
      return rec.isEmpty
          ? _json({
              'error': {'code': 'GLUCOSE_NOT_FOUND', 'message': 'x'},
            }, 404)
          : _json(rec.first);
    }
    if (path.startsWith('/api/me/') && !identityHandles(path)) {
      return _json({
        'error': {'code': 'NOT_FOUND', 'message': 'Tidak ada di backend E2E.'},
      }, 404);
    }
    final copy = http.Request(r.method, r.url)
      ..headers.addAll(r.headers)
      ..body = r.body;
    return http.Response.fromStream(await identity.client.send(copy));
  }

  bool identityHandles(String path) =>
      path.startsWith('/api/me/consents') ||
      path.startsWith('/api/me/onboarding') ||
      path.startsWith('/api/me/profile') ||
      path.startsWith('/api/me/health-profile') ||
      path.startsWith('/api/me/preferences') ||
      path.startsWith('/api/me/account');
}
