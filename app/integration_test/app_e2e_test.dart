import 'dart:convert';
import 'dart:math';

import 'package:app/app.dart';
import 'package:app/core/notifications/reminder_scheduler.dart';
import 'package:app/core/offline/offline_queue.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/offline/sync_controller.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/core/widgets/app_text_field.dart';
import 'package:app/features/app_lock/app_lock.dart';
import 'package:app/features/devices/application/devices_controller.dart';
import 'package:app/features/notifications/application/realtime_controller.dart';
import 'package:app/features/notifications/data/realtime_connector.dart';
import 'package:app/features/push/data/push_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../test/support/fake_backend.dart';
import '../test/support/fake_scheduler.dart';
import 'e2e_backend.dart';

final _password = List.generate(
  32,
  (_) => Random.secure().nextInt(16).toRadixString(16),
).join();

class _NoPush implements PushClient {
  @override
  Future<bool> available() async => false;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<String?> token() async => null;
  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
  @override
  Future<void> deleteToken() async {}
  @override
  Stream<Map<String, dynamic>> get onOpened => const Stream.empty();
  @override
  Future<Map<String, dynamic>?> openedAtLaunch() async => null;
}

class _NoLock implements DeviceAuthenticator {
  @override
  Future<bool> available() async => false;
  @override
  Future<bool> authenticate(String reason) async => true;
}

Future<void> _seed(FakeBackend b, String email) async {
  Future<http.StreamedResponse> call(
    String method,
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) => b.client.send(
    http.Request(method, Uri.parse('http://test$path'))
      ..headers['Content-Type'] = 'application/json'
      ..headers['Authorization'] = token == null ? '' : 'Bearer $token'
      ..body = jsonEncode(body),
  );
  await call('POST', '/api/auth/sign-up/email', {
    'name': 'Rina',
    'email': email,
    'password': _password,
  });
  b.verifyEmail(email);
  final signIn = await call('POST', '/api/auth/sign-in/email', {
    'email': email,
    'password': _password,
  });
  final token = signIn.headers['set-auth-token']!;
  await call('POST', '/api/me/consents', {
    'policyVersion': FakeBackend.policyVersion,
    'purposes': ['health_data_processing', 'descriptive_summaries'],
    'source': 'onboarding',
  }, token: token);
  await call('PATCH', '/api/me/profile', {
    'displayName': 'Rina',
    'birthYear': 1985,
  }, token: token);
  await call('PUT', '/api/me/health-profile', {
    'diagnosisStatus': 'diagnosed',
    'diabetesType': 'type_2',
    'diagnosedYear': 2019,
    'treatmentContext': ['lifestyle'],
  }, token: token);
  await call('PATCH', '/api/me/preferences', {
    'timezone': 'Asia/Jakarta',
    'glucoseUnit': 'mg/dL',
  }, token: token);
  await call('POST', '/api/me/onboarding/complete', {}, token: token);
  await call('POST', '/api/auth/sign-out', {}, token: token);
}

Future<void> _settle(WidgetTester t, [int frames = 40]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _fill(WidgetTester t, String label, String value) async {
  final f = find.descendant(
    of: find.byWidgetPredicate((w) => w is AppTextField && w.label == label),
    matching: find.byType(TextFormField),
  );
  await t.ensureVisible(f);
  await t.enterText(f, value);
  await t.pump(const Duration(milliseconds: 80));
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f.first);
  await t.pump(const Duration(milliseconds: 80));
  await t.tap(f.hitTestable().first);
  await _settle(t);
}

Future<E2EBackend> _start(WidgetTester tester) async {
  await initializeDateFormatting('id_ID');
  final backend = E2EBackend();
  await _seed(backend.identity, 'rina@example.test');
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        tokenStorageProvider.overrideWithValue(MemoryTokenStorage()),
        keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
        reminderSchedulerProvider.overrideWithValue(FakeReminderScheduler()),
        httpClientProvider.overrideWithValue(backend.client),
        realtimeConnectorProvider.overrideWithValue(SilentRealtimeConnector()),
        healthSignalsSourceProvider.overrideWithValue(null),
        deviceAuthenticatorProvider.overrideWithValue(_NoLock()),
        pushClientProvider.overrideWithValue(_NoPush()),
      ],
      child: const BeOkayApp(),
    ),
  );
  await _settle(tester);
  await _tap(tester, find.text('Sudah punya akun? Masuk'));
  await _fill(tester, 'Email', 'rina@example.test');
  await _fill(tester, 'Kata sandi', _password);
  await _tap(tester, find.text('Masuk'));
  await _settle(tester, 60);
  return backend;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('E2E 1: masuk dengan akun terverifikasi membuka Beranda', (
    tester,
  ) async {
    await _start(tester);
    expect(find.text('Hari ini'), findsWidgets);
    expect(find.byTooltip('Notifikasi'), findsWidgets);
  });

  testWidgets(
    'E2E 2: glukosa dicatat saat luring tersimpan di perangkat, lalu terkirim lewat sinkron saat tersambung',
    (tester) async {
      final backend = await _start(tester);
      backend.offline = true;
      final container = ProviderScope.containerOf(
        tester.element(find.byType(BeOkayApp)),
      );
      final router = container.read(routerProvider);
      router.push('/glucose/new');
      await _settle(tester);
      await _fill(tester, 'Nilai pengukuran', '112');
      await _tap(tester, find.text('Simpan glukosa'));
      expect(
        find.text('Tersimpan di perangkat. Akan dikirim saat tersambung.'),
        findsWidgets,
      );
      expect(container.read(syncControllerProvider).pending, 1);
      backend.offline = false;
      await container.read(syncControllerProvider.notifier).flush();
      await _settle(tester);
      expect(backend.syncBatches, hasLength(1));
      expect((backend.syncBatches.single.single as Map)['domain'], 'glucose');
      expect(backend.glucose.single['originalValue'], 112);
      expect(container.read(syncControllerProvider).pending, 0);
    },
  );

  testWidgets(
    'E2E 3: kotak masuk menampilkan notifikasi dan menandainya dibaca',
    (tester) async {
      final backend = await _start(tester);
      await _tap(tester, find.byTooltip('Notifikasi'));
      expect(find.text('Refleksi mingguan siap'), findsOneWidget);
      await _tap(tester, find.text('Refleksi mingguan siap'));
      expect(backend.readIds, ['n1']);
    },
  );
}
