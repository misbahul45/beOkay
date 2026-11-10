import 'dart:convert';

import 'package:app/core/notifications/reminder_scheduler.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/auth/data/session_user.dart';
import 'package:app/features/reminders/application/reminders_controller.dart';
import 'package:app/features/reminders/presentation/reminders_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fake_scheduler.dart';

class _Auth extends AuthController {
  @override
  AuthState build() => const AuthAuthenticated(
    SessionUser(id: 'a', email: 'a@x.test', name: 'A', emailVerified: true),
  );
}

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _rem(
  String id,
  String title, {
  bool enabled = true,
  int version = 1,
}) => {
  'id': id,
  'kind': 'glucose',
  'title': title,
  'localTime': '07:30',
  'daysOfWeek': [1, 2, 3],
  'enabled': enabled,
  'version': version,
};

Future<(ProviderContainer, FakeReminderScheduler, List<http.Request>)> _setup(
  http.Response Function(http.Request) handler,
) async {
  final tokens = MemoryTokenStorage();
  await tokens.write('t');
  final scheduler = FakeReminderScheduler();
  final seen = <http.Request>[];
  final c = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith(_Auth.new),
      tokenStorageProvider.overrideWithValue(tokens),
      reminderSchedulerProvider.overrideWithValue(scheduler),
      // Consent/preferensi tidak relevan di sini; daftar dibaca langsung dari repositori.
      remindersProvider.overrideWith(
        (ref) => ref.watch(remindersRepositoryProvider).list(),
      ),
      httpClientProvider.overrideWithValue(
        MockClient((r) async {
          seen.add(r);
          return handler(r);
        }),
      ),
    ],
  );
  addTearDown(c.dispose);
  return (c, scheduler, seen);
}

List<Map<String, dynamic>> _occurrences() => [
  for (var i = 1; i <= 3; i++)
    {
      'reminderId': 'r1',
      'at': DateTime.now().toUtc().add(Duration(days: i)).toIso8601String(),
      'title': 'Pengingat beOkay',
      'body': 'Buka beOkay untuk mencatat.',
    },
];

void main() {
  test(
    'Signing in schedules the server-computed occurrences with the generic lock-screen text',
    () async {
      final (c, scheduler, _) = await _setup(
        (r) => r.url.path == '/api/me/reminders/upcoming'
            ? _json({'items': _occurrences()})
            : _json({}, 404),
      );
      c.listen(reminderSyncProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(scheduler.scheduled, hasLength(3));
      expect(scheduler.scheduled.first.title, 'Pengingat beOkay');
      expect(scheduler.scheduled.first.body, 'Buka beOkay untuk mencatat.');
      expect(scheduler.scheduled.first.at.isUtc, isTrue);
    },
  );

  test('A 403 (consent withdrawn) cancels every local notification', () async {
    final (c, scheduler, _) = await _setup(
      (r) => _json({
        'error': {'code': 'CONSENT_REQUIRED', 'message': 'x'},
      }, 403),
    );
    await scheduler.replaceAll([
      ScheduledReminder(
        at: DateTime.now().toUtc().add(const Duration(days: 1)),
        title: 't',
        body: 'b',
      ),
    ]);
    c.listen(reminderSyncProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(scheduler.scheduled, isEmpty);
    expect(scheduler.cancelCount, greaterThan(0));
  });

  test('A network failure keeps the schedule already on the device', () async {
    final (c, scheduler, _) = await _setup(
      (r) => throw http.ClientException('no route'),
    );
    await scheduler.replaceAll([
      ScheduledReminder(
        at: DateTime.now().toUtc().add(const Duration(days: 1)),
        title: 't',
        body: 'b',
      ),
    ]);
    c.listen(reminderSyncProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(scheduler.scheduled, hasLength(1));
  });

  testWidgets(
    'Screen lists reminders, toggling sends expectedVersion and resyncs',
    (tester) async {
      var enabled = true;
      final (c, scheduler, seen) = await _setup((r) {
        if (r.url.path == '/api/me/reminders' && r.method == 'GET') {
          return _json({
            'items': [_rem('r1', 'Gula pagi', enabled: enabled)],
            'limit': 20,
          });
        }
        if (r.url.path == '/api/me/reminders/r1' && r.method == 'PATCH') {
          enabled = (jsonDecode(r.body) as Map)['enabled'] as bool;
          return _json(_rem('r1', 'Gula pagi', enabled: enabled, version: 2));
        }
        if (r.url.path == '/api/me/reminders/upcoming') {
          return _json({'items': enabled ? _occurrences() : []});
        }
        return _json({}, 404);
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: RemindersScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('07:30 · Gula pagi'), findsOneWidget);
      expect(find.textContaining('Glukosa · Sen, Sel, Rab'), findsOneWidget);
      expect(find.textContaining('tanpa nama obat atau angka'), findsNothing);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      final patch = seen.firstWhere((r) => r.method == 'PATCH');
      expect(jsonDecode(patch.body), {'expectedVersion': 1, 'enabled': false});
      expect(scheduler.scheduled, isEmpty);
    },
  );

  testWidgets(
    'Creating the first reminder validates input, saves, and asks for notification permission',
    (tester) async {
      Map<String, dynamic>? created;
      final items = <Map<String, dynamic>>[];
      final (c, scheduler, seen) = await _setup((r) {
        if (r.url.path == '/api/me/reminders' && r.method == 'GET') {
          return _json({'items': items, 'limit': 20});
        }
        if (r.url.path == '/api/me/reminders' && r.method == 'POST') {
          created = jsonDecode(r.body) as Map<String, dynamic>;
          items.add(_rem('r9', created!['title'] as String));
          return _json(items.last, 201);
        }
        if (r.url.path == '/api/me/reminders/upcoming') {
          return _json({'items': []});
        }
        return _json({}, 404);
      });
      scheduler.permission = false;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: Scaffold(body: RemindersScreen())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Belum ada pengingat'), findsOneWidget);

      await tester.tap(find.text('Tambah pengingat').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(find.text('Beri nama pengingat.'), findsOneWidget);
      expect(seen.where((r) => r.method == 'POST'), isEmpty);

      await tester.enterText(find.byType(TextField).first, 'Catat gula pagi');
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(created, {
        'kind': 'glucose',
        'title': 'Catat gula pagi',
        'localTime': '07:30',
        'daysOfWeek': [1, 2, 3, 4, 5, 6, 7],
      });
      expect(
        find.textContaining('notifikasi belum diizinkan'),
        findsOneWidget,
      ); // penolakan izin dikabarkan, aturan tetap tersimpan
      expect(find.text('07:30 · Catat gula pagi'), findsOneWidget);
    },
  );
}
