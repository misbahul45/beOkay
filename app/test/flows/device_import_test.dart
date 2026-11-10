import 'dart:convert';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/features/activity/data/device_activity_source.dart';
import 'package:app/features/activity/presentation/device_import_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Source implements DeviceActivitySource {
  _Source({
    this.state = DeviceSourceStatus.ready,
    this.grant = true,
    this.sessions = const [],
  });
  DeviceSourceStatus state;
  bool grant;
  List<DeviceSession> sessions;
  int asked = 0;
  @override
  String get sourceKey => 'health_connect';
  @override
  String get displayName => 'Health Connect';
  @override
  Future<DeviceSourceStatus> status() async => state;
  @override
  Future<bool> requestAccess() async {
    asked++;
    return grant;
  }

  @override
  Future<List<DeviceSession>> readWorkouts({
    required DateTime from,
    required DateTime to,
  }) async => sessions;
}

DeviceSession _s(String id) => DeviceSession(
  externalId: id,
  activityType: 'walking',
  startedAt: DateTime.utc(2026, 11, 8, 1),
  durationMinutes: 30,
);

Future<(Widget, List<http.Request>)> _app(DeviceActivitySource? source) async {
  final tokens = MemoryTokenStorage();
  await tokens.write('t');
  final seen = <http.Request>[];
  final repo = ActivityImportRepository(
    ApiClient(
      tokens: tokens,
      baseUrl: 'http://test',
      client: MockClient((r) async {
        seen.add(r);
        return http.Response(
          jsonEncode({
            'summary': {
              'created': 1,
              'createdNeedsReview': 1,
              'duplicate': 0,
              'rejected': 0,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    ),
    isCurrentAccount: () => true,
  );
  return (
    ProviderScope(
      overrides: [
        deviceActivitySourceProvider.overrideWithValue(source),
        activityImportRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: DeviceImportSection()),
        ),
      ),
    ),
    seen,
  );
}

void main() {
  test('Workout type mapping never guesses: unknown becomes "other"', () {
    expect(mapWorkoutType('WALKING'), 'walking');
    expect(mapWorkoutType('RUNNING_TREADMILL'), 'running');
    expect(mapWorkoutType('BIKING_STATIONARY'), 'cycling');
    expect(mapWorkoutType('TRADITIONAL_STRENGTH_TRAINING'), 'strength');
    expect(mapWorkoutType('YOGA'), 'other');
    expect(mapWorkoutType(''), 'other');
  });

  test(
    'Distance only converts from a clear meter unit; duration is bounded 1..1440',
    () {
      expect(distanceKmFrom(1600, 'METER'), 1.6);
      expect(distanceKmFrom(1600, 'MILE'), isNull);
      expect(distanceKmFrom(1600, null), isNull);
      expect(distanceKmFrom(null, 'METER'), isNull);
      final t = DateTime.utc(2026, 11, 8, 1);
      expect(durationMinutesFrom(t, t.add(const Duration(minutes: 30))), 30);
      expect(
        durationMinutesFrom(t, t.add(const Duration(seconds: 10))),
        isNull,
      );
      expect(durationMinutesFrom(t, t.add(const Duration(hours: 25))), isNull);
      expect(
        durationMinutesFrom(t, t.subtract(const Duration(minutes: 5))),
        isNull,
      );
    },
  );

  test('toJson omits unknown distance and steps instead of sending zero', () {
    expect(_s('a').toJson().containsKey('distanceKm'), isFalse);
    expect(_s('a').toJson().containsKey('steps'), isFalse);
    expect(_s('a').toJson()['startedAt'], '2026-11-08T01:00:00.000Z');
  });

  testWidgets('Hidden when the platform has no supported source', (
    tester,
  ) async {
    final (app, _) = await _app(null);
    await tester.pumpWidget(app);
    expect(find.textContaining('Impor dari'), findsNothing);
  });

  testWidgets(
    'Imports 30-day workouts once the user taps, asks permission first, and reports the result',
    (tester) async {
      final src = _Source(
        state: DeviceSourceStatus.needsPermission,
        sessions: [_s('u1'), _s('u2')],
      );
      final (app, seen) = await _app(src);
      await tester.pumpWidget(app);
      expect(seen, isEmpty); // tidak ada panggilan sebelum ditekan
      await tester.tap(find.text('Impor dari Health Connect'));
      await tester.pumpAndSettle();
      expect(src.asked, 1);
      final body = jsonDecode(seen.single.body) as Map<String, dynamic>;
      expect(body['source'], 'health_connect');
      expect((body['sessions'] as List).length, 2);
      expect(
        find.textContaining('Dibaca 2 sesi: 1 ditambahkan, 1 perlu diperiksa'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Denied permission, missing app, and empty history are reported without calling the server',
    (tester) async {
      for (final (src, text) in [
        (
          _Source(state: DeviceSourceStatus.needsPermission, grant: false),
          'Izin membaca sesi olahraga belum diberikan.',
        ),
        (
          _Source(state: DeviceSourceStatus.notInstalled),
          'belum terpasang atau belum aktif',
        ),
        (_Source(), 'Tidak ada sesi olahraga'),
      ]) {
        final (app, seen) = await _app(src);
        await tester.pumpWidget(app);
        await tester.tap(find.text('Impor dari Health Connect'));
        await tester.pumpAndSettle();
        expect(find.textContaining(text), findsOneWidget);
        expect(seen, isEmpty);
      }
    },
  );
}
