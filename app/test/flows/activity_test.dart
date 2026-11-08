import 'package:app/features/activity/data/activity_models.dart';
import 'package:app/features/activity/presentation/activity_form_screen.dart';
import 'package:app/core/widgets/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:convert';
import 'package:app/core/network/api_client.dart';
import 'package:app/core/storage/token_storage.dart';
import 'package:app/core/ids/record_id.dart';
import 'package:app/features/activity/application/activity_controller.dart';
import 'package:app/features/activity/data/activity_repository.dart';
import 'package:app/features/activity/presentation/activity_week_screen.dart';
import 'package:app/features/activity/presentation/activity_history_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ActivitySummary emptyWeek(String start) {
  Map<String, dynamic> metric() => {
    'value': null,
    'knownSessions': 0,
    'totalSessions': 0,
    'coverage': 'UNKNOWN',
  };
  Map<String, dynamic> totals() => {
    'count': 0,
    'eligibleCount': 0,
    'reviewCount': 0,
    'durationMinutes': null,
    'distanceKm': metric(),
    'steps': metric(),
  };
  String day(int i) {
    final date = DateTime.parse('${start}T00:00:00Z').add(Duration(days: i));
    return date.toIso8601String().substring(0, 10);
  }

  return ActivitySummary.fromJson({
    ...totals(),
    'date': start,
    'startDate': start,
    'endDate': day(7),
    'timezone': 'America/New_York',
    'firstDay': 7,
    'activeDays': 0,
    'computedAt': '2026-11-01T00:00:00Z',
    'computationVersion': 'activity-test',
    'days': [
      for (var i = 0; i < 7; i++) {...totals(), 'date': day(i)},
    ],
  });
}

void main() {
  testWidgets('Future selected-week history can open its date filter safely', (
    tester,
  ) async {
    await initializeDateFormatting('id_ID');
    final future = DateTime.now()
        .add(const Duration(days: 30))
        .toIso8601String()
        .substring(0, 10);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => ActivityHistoryScreen(initialDate: future),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activityDayProvider.overrideWith(
            (ref, date) async => emptyWeek(future),
          ),
          activityPageProvider.overrideWith(
            (ref, query) async => ActivityPage.fromJson({
              'items': [],
              'nextCursor': null,
              'timezone': 'Asia/Jakarta',
            }),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(future));
    await tester.tap(find.text(future));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });
  testWidgets(
    'Next activity week uses calendar days across device DST fallback',
    (tester) async {
      await initializeDateFormatting('id_ID');
      final requested = <String?>[];
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const ActivityWeekScreen()),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activityWeekProvider.overrideWith((ref, date) async {
              requested.add(date);
              return emptyWeek('2026-11-01');
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Minggu berikutnya'));
      await tester.tap(find.text('Minggu berikutnya'));
      await tester.pumpAndSettle();
      expect(requested.last, '2026-11-08');
    },
  );
  test(
    'Activity rejects writes after account changes before sending HTTP',
    () async {
      final tokens = MemoryTokenStorage();
      await tokens.write(newRecordId());
      var sent = false;
      final repo = ActivityRepository(
        ApiClient(
          tokens: tokens,
          baseUrl: 'http://test',
          client: MockClient((_) async {
            sent = true;
            return http.Response('{}', 200);
          }),
        ),
        isCurrentAccount: () => false,
      );
      await expectLater(
        repo.write('POST', '/api/me/activities', {}),
        throwsA(isA<Exception>()),
      );
      expect(sent, isFalse);
    },
  );
  for (final status in [400, 409, 503]) {
    testWidgets(
      'Activity correction handles HTTP $status and preserves retry payload',
      (tester) async {
        await initializeDateFormatting('id_ID');
        final tokens = MemoryTokenStorage();
        await tokens.write(newRecordId());
        final payloads = <String>[];
        final repo = ActivityRepository(
          ApiClient(
            tokens: tokens,
            baseUrl: 'http://test',
            client: MockClient((request) async {
              payloads.add(request.body);
              return http.Response(
                jsonEncode({
                  'error': {
                    'code': status == 409
                        ? 'VERSION_CONFLICT'
                        : 'SYNTHETIC_ERROR',
                    'message': 'Synthetic test',
                  },
                }),
                status,
              );
            }),
          ),
          isCurrentAccount: () => true,
        );
        final record = ActivityRecord.fromJson({
          'id': newRecordId(),
          'activityType': 'walking',
          'startedAt': '2026-01-04T01:00:00Z',
          'endedAt': '2026-01-04T01:30:00Z',
          'durationMinutes': 30,
          'reportedIntensity': 'unknown',
          'qualityStatus': 'user_reported',
          'version': 1,
          'localDate': '2026-01-04',
          'localTime': '08:00',
          'endLocalDate': '2026-01-04',
          'endLocalTime': '08:30',
          'timezone': 'Asia/Jakarta',
        });
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => ActivityFormScreen(initial: record),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [activityRepositoryProvider.overrideWithValue(repo)],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        Finder field(String label) => find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is AppTextField && w.label == label,
          ),
          matching: find.byType(TextFormField),
        );
        await tester.ensureVisible(field('Alasan koreksi'));
        await tester.enterText(
          field('Alasan koreksi'),
          'Correct synthetic session',
        );
        await tester.ensureVisible(find.text('Simpan koreksi'));
        await tester.tap(find.text('Simpan koreksi'));
        await tester.pumpAndSettle();
        expect(payloads, hasLength(1));
        expect(
          tester.widget<TextFormField>(field('Durasi (menit)')).enabled,
          status == 400,
        );
        if (status == 409) {
          expect(find.text('Muat ulang catatan'), findsOneWidget);
        }
        if (status == 503) {
          await tester.ensureVisible(find.text('Simpan koreksi'));
          await tester.tap(find.text('Simpan koreksi'));
          await tester.pumpAndSettle();
          expect(payloads, hasLength(2));
          expect(payloads.last, payloads.first);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('Weekly day selection opens its dated history at large text', (
    tester,
  ) async {
    await initializeDateFormatting('id_ID');
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Map<String, dynamic> metric() => {
      'value': null,
      'knownSessions': 0,
      'totalSessions': 0,
      'coverage': 'UNKNOWN',
    };
    Map<String, dynamic> totals() => {
      'count': 0,
      'eligibleCount': 0,
      'reviewCount': 0,
      'durationMinutes': null,
      'distanceKm': metric(),
      'steps': metric(),
    };
    final summary = ActivitySummary.fromJson({
      ...totals(),
      'date': '2026-01-04',
      'startDate': '2026-01-04',
      'endDate': '2026-01-11',
      'timezone': 'Asia/Jakarta',
      'firstDay': 7,
      'activeDays': 0,
      'computedAt': '2026-01-04T00:00:00Z',
      'computationVersion': 'activity-test',
      'days': [
        for (var i = 0; i < 7; i++)
          {
            ...totals(),
            'date': '2026-01-${(4 + i).toString().padLeft(2, '0')}',
          },
      ],
    });
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const ActivityWeekScreen()),
        GoRoute(
          path: '/activities',
          builder: (_, s) =>
              Scaffold(body: Text('History ${s.uri.queryParameters['date']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activityWeekProvider.overrideWith((ref, date) async => summary),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final monday = find.textContaining('Sen 5');
    await tester.ensureVisible(monday);
    await tester.tap(monday);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Lihat sesi hari ini'));
    await tester.tap(find.text('Lihat sesi hari ini'));
    await tester.pumpAndSettle();
    expect(find.text('History 2026-01-05'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('Activity input keeps unknown metrics separate from reported zero', () {
    expect(validateActivityDuration('30'), isNull);
    for (final value in ['0', '-1', '1.5', '1441', 'NaN']) {
      expect(validateActivityDuration(value), isNotNull);
    }
    expect(validateActivityMetric('', steps: false), isNull);
    expect(validateActivityMetric('0', steps: true), isNull);
    expect(validateActivityMetric('-1', steps: false), isNotNull);
    expect(validateActivityMetric('1.5', steps: true), isNotNull);
  });
  testWidgets(
    'Activity form validates before submission and supports large text',
    (tester) async {
      await initializeDateFormatting('id_ID');
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const ActivityFormScreen()),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is AppTextField && w.label == 'Durasi (menit)',
        ),
        matching: find.byType(TextFormField),
      );
      await tester.ensureVisible(field);
      await tester.enterText(field, '0');
      await tester.ensureVisible(find.text('Simpan aktivitas'));
      await tester.tap(find.text('Simpan aktivitas'));
      await tester.pumpAndSettle();
      expect(
        find.text('Isi durasi 1–1440 menit dalam bilangan bulat.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
