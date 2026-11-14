import 'dart:convert';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/offline/offline_queue.dart';
import 'package:app/core/offline/sync_controller.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/core/widgets/settings_group.dart';
import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/auth/data/session_user.dart';
import 'package:app/features/devices/application/devices_controller.dart';
import 'package:app/features/devices/data/health_source.dart';
import 'package:app/features/devices/presentation/devices_screen.dart';
import 'package:app/features/devices/presentation/heart_rate_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

const _token = String.fromEnvironment('E2E_TOKEN');
const _phase = String.fromEnvironment('E2E_PHASE', defaultValue: 'connect');
const _base = String.fromEnvironment(
  'E2E_API',
  defaultValue: 'http://localhost:3000',
);
const _hold = int.fromEnvironment('E2E_HOLD_SECONDS', defaultValue: 0);

class _Auth extends AuthController {
  @override
  AuthState build() => const AuthAuthenticated(
    SessionUser(
      id: 'e2e',
      email: 'e2e@x.test',
      name: 'E2E',
      emailVerified: true,
    ),
  );
}

Future<void> _until(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 120),
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('timeout menunggu kondisi');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 300));
}

Finder _switchOf(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(SettingsRow)),
  matching: find.byType(Switch),
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Health Connect nyata di emulator: $_phase', (tester) async {
    expect(
      _token,
      isNotEmpty,
      reason: 'E2E_TOKEN wajib diberikan lewat --dart-define',
    );
    final tokens = MemoryTokenStorage();
    await tokens.write(_token);
    final api = ApiClient(
      client: http.Client(),
      tokens: tokens,
      baseUrl: _base,
    );
    Future<Map<String, dynamic>> get(String path) async =>
        (await api.get(path)).object;

    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const DevicesScreen()),
        GoRoute(
          path: Routes.heartRate,
          builder: (_, _) => const HeartRateScreen(),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_Auth.new),
          apiClientProvider.overrideWithValue(api),
          keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    await _until(
      tester,
      () => !container.read(deviceConnectionProvider).loading,
    );
    final out = <String, Object?>{'phase': _phase};

    Future<void> toggle(String label) async {
      await tester.ensureVisible(_switchOf(label));
      await tester.pump();
      await tester.tap(_switchOf(label));
      await tester.pump();
      await _until(
        tester,
        () => !container.read(deviceConnectionProvider).syncing,
      );
      out['toggle:$label'] = container.read(deviceConnectionProvider).message;
    }

    Future<void> syncAgain() async {
      await tester.ensureVisible(find.text('Sinkronkan sekarang'));
      await tester.pump();
      await tester.tap(find.text('Sinkronkan sekarang'));
      await tester.pump();
      await _until(
        tester,
        () => !container.read(deviceConnectionProvider).syncing,
      );
    }

    Future<Map<String, Object?>> snapshot() async {
      final hr = await get('/api/me/heart-rate?days=7');
      final steps = await get('/api/me/steps?days=7');
      final sleep = await get('/api/me/sleep?days=7');
      final status = await get('/api/me/devices/status');
      final acts = await get('/api/me/activities?limit=50');
      final series = (hr['series'] as List).cast<Map<String, dynamic>>();
      return {
        'hrSamples': series.fold<int>(
          0,
          (a, d) => a + (d['sampleCount'] as int),
        ),
        'hrBuckets': series.fold<int>(
          0,
          (a, d) => a + (d['observedBuckets'] as int),
        ),
        'hrLatest': (hr['latest'] as Map?)?['bpm'],
        'resting': (hr['restingLatest'] as Map?)?['bpm'],
        'stepsToday': (steps['series'] as List).last['steps'],
        'stepsYesterday':
            (steps['series'] as List)[(steps['series'] as List).length -
                2]['steps'],
        'sleepSessions': (sleep['sessions'] as List).length,
        'activities':
            ((acts['items'] ?? acts['data'] ?? const []) as List).length,
        'watch': status['watchVerification'],
        'syncState': status['syncState'],
        'permissionState': status['permissionState'],
        'detectedDeviceTypes': status['detectedDeviceTypes'],
        'sourceApps': (status['sourceApplications'] as List)
            .map((s) => '${(s as Map)['dataOrigin']}|${s['provenance']}')
            .toList(),
        'simulated': status['simulated'],
      };
    }

    if (_phase == 'connect') {
      await api.patch(
        '/api/me/device-import/preferences',
        body: {
          'steps': false,
          'heartRate': false,
          'restingHeartRate': false,
          'sleep': false,
          'workouts': false,
          'weight': false,
          'glucose': false,
        },
      );
      await container.read(deviceConnectionProvider.notifier).refresh();
      await tester.pump();
      expect(find.text('Health Connect tersedia'), findsOneWidget);
      expect(find.text('Belum ada data yang diimpor'), findsOneWidget);
      for (final label in [
        'Langkah',
        'Detak jantung',
        'Detak jantung istirahat',
        'Tidur',
        'Aktivitas olahraga',
      ]) {
        await toggle(label);
      }
      final src = container.read(healthDataSourceProvider)!;
      final probe = await src.read(
        HealthReadRequest(
          metrics: const {WearableMetric.workouts},
          from: DateTime.now().subtract(const Duration(days: 14)),
          to: DateTime.now(),
        ),
      );
      out['workoutProbe'] = {
        'count': probe.workouts.length,
        'errors': probe.errors.map((k, v) => MapEntry(k.name, v)),
        'types': probe.workouts
            .map(
              (w) => '${w.activityType}:${w.durationMinutes}:${w.deviceType}',
            )
            .toList(),
      };
      final first = await snapshot();
      out['afterEnable'] = first;
      await syncAgain();
      final second = await snapshot();
      out['afterResync'] = second;
      out['message'] = container.read(deviceConnectionProvider).message;
      out['state'] = container.read(deviceConnectionProvider).state.name;
      expect(second['hrSamples'], first['hrSamples']);
      expect(second['sleepSessions'], first['sleepSessions']);
      expect(second['stepsToday'], first['stepsToday']);
      expect(second['activities'], first['activities']);
    } else if (_phase == 'revoked') {
      await tester.ensureVisible(find.text('Sinkronkan sekarang'));
      await tester.pump();
      await tester.tap(find.text('Sinkronkan sekarang'));
      await tester.pump();
      await _until(
        tester,
        () => !container.read(deviceConnectionProvider).syncing,
      );
      out['message'] = container.read(deviceConnectionProvider).message;
      out['state'] = container.read(deviceConnectionProvider).state.name;
      out['snapshot'] = await snapshot();
    } else if (_phase == 'recovered') {
      await tester.ensureVisible(find.text('Sinkronkan sekarang'));
      await tester.pump();
      await tester.tap(find.text('Sinkronkan sekarang'));
      await tester.pump();
      await _until(
        tester,
        () => !container.read(deviceConnectionProvider).syncing,
      );
      out['message'] = container.read(deviceConnectionProvider).message;
      out['state'] = container.read(deviceConnectionProvider).state.name;
      out['snapshot'] = await snapshot();
    }

    debugPrint('E2E_RESULT ${jsonEncode(out)}');
    if (_hold > 0) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: _hold)),
      );
    }
  });
}
