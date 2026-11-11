import 'package:app/features/insights/application/insights_controller.dart';
import 'package:app/features/insights/data/statistics.dart';
import 'package:app/features/insights/presentation/insight_presentation.dart';
import 'package:app/features/insights/presentation/summary_tab.dart';
import 'package:app/features/nutrition/data/nutrition_models.dart';
import 'package:app/features/today/presentation/today_extras.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

Map<String, dynamic> _stat(
  String id,
  String domain,
  String label,
  num? value,
  String? unit, {
  bool ready = true,
  int sample = 5,
  int min = 0,
  Map<String, dynamic>? comparison,
  Map<String, dynamic>? detail,
  String coverage = 'PARTIAL',
}) => {
  'id': id,
  'domain': domain,
  'label': label,
  'value': value,
  'unit': unit,
  'category': 'DESCRIPTIVE_AGGREGATE',
  'state': ready ? 'READY' : 'INSUFFICIENT_DATA',
  'range': {'start': '2026-11-04', 'end': '2026-11-10', 'days': 7},
  'sourceType': domain == 'glucose'
      ? 'MANUAL_GLUCOMETER'
      : 'USER_AND_DEVICE_ACTIVITY',
  'sampleCount': sample,
  'sampleUnit': 'hari',
  'minimumSample': min,
  'coverage': {'status': coverage, 'daysWithData': 3, 'totalDays': 7},
  'derivation': 'Cara hitung $id.',
  'comparison': comparison,
  'detail': detail,
  'limitations': ['Batasan $id.'],
  'analysisVersion': 'stats-v1',
  'computedAt': '2026-11-10T11:00:00.000Z',
};

Map<String, dynamic> _json(int days, {bool ready = true, bool cards = true}) {
  final start = DateTime(2026, 11, 10).subtract(Duration(days: days - 1));
  String d(int i) =>
      start.add(Duration(days: i)).toIso8601String().substring(0, 10);
  return {
    'analysisVersion': 'stats-v1',
    'period': {'start': d(0), 'end': d(days - 1), 'days': days},
    'comparisonPeriod': {'start': '2026-10-28', 'end': '2026-11-03', 'days': 7},
    'analyticsState': ready ? 'READY' : 'INSUFFICIENT_DATA',
    'glucoseUnit': 'mg/dL',
    'computedAt': '2026-11-10T11:00:00.000Z',
    'statistics': [
      _stat(
        'activity.total_minutes',
        'activity',
        'Durasi aktivitas tercatat',
        ready ? 80 : null,
        'menit',
        ready: ready,
        comparison: ready
            ? {
                'value': 105,
                'change': -25,
                'direction': 'DOWN',
                'range': {
                  'start': '2026-10-28',
                  'end': '2026-11-03',
                  'days': 7,
                },
              }
            : null,
      ),
      _stat(
        'activity.active_days',
        'activity',
        'Hari aktif tercatat',
        ready ? 3 : 0,
        'hari',
      ),
      _stat(
        'glucose.readings',
        'glucose',
        'Pengukuran glukosa tercatat',
        ready ? 2 : 0,
        'pengukuran',
      ),
      _stat(
        'nutrition.logged_days',
        'nutrition',
        'Hari dengan catatan makan',
        ready ? 4 : 0,
        'hari',
      ),
      _stat(
        'logging.recorded_days',
        'logging',
        'Hari dengan catatan',
        ready ? 6 : 0,
        'hari',
      ),
      _stat(
        'glucose.fasting_median',
        'glucose',
        'Glukosa puasa (median)',
        null,
        'mg/dL',
        ready: false,
        sample: 2,
        min: 3,
      ),
      _stat(
        'medication.confirmed',
        'medication',
        'Jadwal obat yang dikonfirmasi',
        ready ? 2 : null,
        'jadwal',
        ready: ready,
        detail: {'scheduled': 7, 'taken': 2, 'skipped': 0, 'unconfirmed': 5},
      ),
      _stat(
        'nutrition.calories_per_logged_day',
        'nutrition',
        'Energi tercatat per hari tercatat',
        ready ? 681 : null,
        'kkal',
        ready: ready,
      ),
      _stat(
        'nutrition.fiber_per_logged_day',
        'nutrition',
        'Serat tercatat per hari tercatat',
        null,
        'g',
        ready: false,
        sample: 2,
        min: 3,
      ),
    ],
    'insights': ready && cards
        ? [
            {
              'code': 'ACTIVITY_PERIOD_CHANGE',
              'domain': 'activity',
              'title':
                  'Durasi aktivitas tercatat lebih rendah dari 7 hari sebelumnya.',
              'body': 'Bisa jadi ada sesi yang belum dicatat.',
              'evidence': [
                {'label': '7 hari ini', 'value': '80 menit · 3 hari aktif'},
                {'label': '7 hari sebelumnya', 'value': '105 menit'},
              ],
              'statisticIds': ['activity.total_minutes'],
              'coverage': {'daysWithData': 3, 'totalDays': 7},
              'actions': ['OPEN_TRENDS', 'CREATE_GOAL', 'ASK_COACH'],
              'rulesVersion': 'insight-rules-v1',
            },
            {
              'code': 'NUTRITION_LOGGING_COVERAGE',
              'domain': 'nutrition',
              'title': 'Catatan makan ada di 4 dari 14 hari.',
              'body': 'Rata-rata gizi hanya mewakili hari yang tercatat.',
              'evidence': [
                {'label': 'Hari dengan catatan makan', 'value': '4 dari 14'},
              ],
              'statisticIds': ['nutrition.logged_days'],
              'coverage': {'daysWithData': 4, 'totalDays': 14},
              'actions': ['LOG_MEAL'],
              'rulesVersion': 'insight-rules-v1',
            },
            {
              'code': 'MEDICATION_UNCONFIRMED',
              'domain': 'medication',
              'title': '5 jadwal obat belum dikonfirmasi pada periode ini.',
              'body': 'Belum dikonfirmasi tidak berarti terlewat.',
              'evidence': [
                {'label': 'Dikonfirmasi', 'value': '2 dari 7 jadwal'},
              ],
              'statisticIds': ['medication.confirmed'],
              'coverage': {'daysWithData': 7, 'totalDays': 7},
              'actions': ['OPEN_MEDICATION'],
              'rulesVersion': 'insight-rules-v1',
            },
          ]
        : [],
    'series': [
      for (var i = 0; i < days; i++)
        {
          'date': d(i),
          'recorded': ready && i.isEven,
          'meals': ready && i.isEven ? 1 : 0,
          'nutrients': {
            for (final k in [
              'calories',
              'carbohydrates',
              'protein',
              'fat',
              'fiber',
            ])
              k: ready && i.isEven
                  ? {
                      'value': i == 0 && k == 'fat' ? null : 10.0 + i,
                      'coverage': 'COMPLETE',
                    }
                  : null,
          },
          'activityMinutes': null,
          'glucose': <dynamic>[],
          'medication': {'scheduled': 1, 'taken': 0, 'skipped': 0},
        },
    ],
  };
}

Future<(List<int>, ProviderContainer Function())> _pump(
  WidgetTester tester, {
  bool ready = true,
  bool cards = true,
  double textScale = 1,
  Size size = const Size(390, 2600),
}) async {
  await initializeDateFormatting('id_ID');
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final requested = <int>[];
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: MediaQuery.withClampedTextScaling(
            minScaleFactor: textScale,
            maxScaleFactor: textScale,
            child: const SingleChildScrollView(child: SummaryTab()),
          ),
        ),
      ),
      GoRoute(
        path: '/medications',
        builder: (_, _) => const Scaffold(body: Text('Halaman obat')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        statisticsProvider.overrideWith((ref, days) async {
          requested.add(days);
          return Statistics.fromJson(_json(days, ready: ready, cards: cards));
        }),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 900));
  return (
    requested,
    () => ProviderScope.containerOf(tester.element(find.byType(SummaryTab))),
  );
}

Statistics _stats({bool cards = true, int activeDays = 3}) {
  final j = _json(14, cards: cards);
  for (final st in j['statistics'] as List) {
    if ((st as Map)['id'] == 'activity.total_minutes') {
      (st['coverage'] as Map)['daysWithData'] = activeDays;
    }
  }
  return Statistics.fromJson(j);
}

void main() {
  testWidgets(
    'Ringkasan: one page-level coverage line, top two insights with one action each, compact metrics, no analysis metadata',
    (tester) async {
      await _pump(tester);
      expect(find.text('Ada catatan di 6 dari 14 hari'), findsOneWidget);
      expect(find.textContaining('ada data'), findsNothing);
      expect(find.textContaining('stats-v1'), findsNothing);
      expect(find.textContaining('Dihitung dari catatanmu'), findsNothing);
      expect(find.text('5 jadwal belum dikonfirmasi'), findsOneWidget);
      expect(find.text('80 menit tercatat'), findsOneWidget);
      expect(
        find.text('25 menit lebih sedikit dari catatan 14 hari sebelumnya.'),
        findsOneWidget,
      );
      expect(find.text('Makan tercatat di 4 dari 14 hari'), findsNothing);
      expect(find.text('Buka obat'), findsOneWidget);
      expect(find.text('Lihat tren'), findsOneWidget);
      expect(find.text('Buat target'), findsNothing);
      expect(find.text('Tanya Asisten'), findsNothing);
      await tester.tap(find.text('Lihat semua wawasan (3)'));
      await tester.pumpAndSettle();
      expect(find.text('Makan tercatat di 4 dari 14 hari'), findsOneWidget);
      expect(find.text('80 menit', findRichText: true), findsOneWidget);
      expect(find.text('3 hari tercatat'), findsOneWidget);
      expect(find.text('2 dari 7'), findsOneWidget);
      expect(find.text('Jadwal dikonfirmasi'), findsOneWidget);
      expect(find.text('Median puasa belum cukup data'), findsOneWidget);
      expect(
        find.textContaining(RegExp('skor|kepatuhan', caseSensitive: false)),
        findsNothing,
      );
    },
  );

  testWidgets('"Lihat tren" switches Wawasan to the Tren section', (
    tester,
  ) async {
    final (_, container) = await _pump(tester);
    await tester.tap(find.text('Lihat tren'));
    await tester.pump();
    expect(container().read(insightsSectionProvider), InsightsSection.trends);
  });

  testWidgets(
    'Metric detail shows context first; methodology stays under "Tentang data" and never shows the version',
    (tester) async {
      await _pump(tester);
      await tester.ensureVisible(find.text('3 hari tercatat'));
      await tester.tap(find.text('3 hari tercatat'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          '25 menit lebih sedikit dari catatan 14 hari sebelumnya (105 menit).',
        ),
        findsOneWidget,
      );
      expect(find.text('Data ada untuk 3 dari 7 hari'), findsOneWidget);
      expect(find.text('Cara hitung activity.total_minutes.'), findsNothing);
      expect(find.text('Terakhir diperbarui'), findsNothing);
      await tester.tap(find.text('Tentang data'));
      await tester.pumpAndSettle();
      expect(find.text('Cara hitung activity.total_minutes.'), findsOneWidget);
      expect(find.text('Sesi manual dan impor perangkat'), findsOneWidget);
      expect(
        find.textContaining('Batasan activity.total_minutes.'),
        findsOneWidget,
      );
      expect(find.textContaining('stats-v1'), findsNothing);
      expect(find.text('Terakhir diperbarui'), findsOneWidget);
    },
  );

  testWidgets(
    'Nutrition detail shows macronutrient grams per day with a table, and missing days stay missing',
    (tester) async {
      await _pump(tester);
      await tester.ensureVisible(find.text('Dengan catatan makan'));
      await tester.tap(find.text('Dengan catatan makan'));
      await tester.pumpAndSettle();
      expect(find.text('Makronutrien tercatat'), findsOneWidget);
      expect(
        find.text('Gram per hari. Hari tanpa catatan ditandai –.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Lihat sebagai tabel'));
      await tester.tap(find.text('Lihat sebagai tabel'));
      await tester.pumpAndSettle();
      expect(find.text('–'), findsWidgets);
      expect(find.text('tidak diketahui'), findsOneWidget);
    },
  );

  testWidgets('The period selector drives the request', (tester) async {
    final (requested, _) = await _pump(tester);
    expect(requested.last, 14);
    await tester.tap(find.text('7 hari'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(requested.last, 7);
  });

  testWidgets(
    'At 2x text the period selector wraps into two rows and nothing overflows',
    (tester) async {
      await _pump(tester, textScale: 2, size: const Size(360, 3600));
      expect(tester.takeException(), isNull);
      final first = tester.getCenter(find.text('7 hari'));
      final third = tester.getCenter(find.text('30 hari'));
      expect(third.dy, greaterThan(first.dy));
      expect(find.text('80 menit tercatat'), findsOneWidget);
    },
  );

  testWidgets('No records: honest empty state with a way to start', (
    tester,
  ) async {
    await _pump(tester, ready: false);
    expect(find.text('Belum ada catatan di 14 hari terakhir'), findsOneWidget);
    expect(find.text('Mulai mencatat'), findsOneWidget);
    expect(find.text('Lihat tren'), findsNothing);
  });

  testWidgets('Without strong patterns the summary says so briefly', (
    tester,
  ) async {
    await _pump(tester, cards: false);
    expect(
      find.text('Belum ada pola yang cukup kuat untuk disebut.'),
      findsOneWidget,
    );
    expect(find.text('Ikhtisar'), findsOneWidget);
  });

  test(
    'Presentation: priority order, one card per domain first, honest copy',
    () {
      final ranked = prioritizeInsights(_stats());
      expect(ranked.map((i) => i.code), [
        'MEDICATION_UNCONFIRMED',
        'ACTIVITY_PERIOD_CHANGE',
        'NUTRITION_LOGGING_COVERAGE',
      ]);
      expect(
        ranked.first.supporting,
        'Belum dikonfirmasi tidak berarti terlewat.',
      );
      expect(ranked.every((i) => i.action != null), isTrue);
      expect(
        ranked.map((i) => i.headline).join(' '),
        isNot(contains('stats-v1')),
      );
    },
  );

  test(
    'Presentation: a comparison built on one recorded day is not claimed',
    () {
      final s = _stats(activeDays: 1);
      final activity = prioritizeInsights(
        s,
      ).firstWhere((i) => i.code == 'ACTIVITY_PERIOD_CHANGE');
      expect(activity.supporting, 'Data ada untuk 1 dari 14 hari.');
      expect(
        comparisonValidity(s.byId('activity.total_minutes')!),
        ComparisonValidity.tooLittleData,
      );
    },
  );

  test('Presentation: missing data stays missing, never zero', () {
    final s = Statistics.fromJson(_json(14, ready: false));
    final metrics = overviewMetrics(s);
    expect(metrics.every((m) => m.value == null), isTrue);
    expect(metrics.map((m) => m.caption), [
      'Belum ada sesi tercatat',
      'Belum ada pengukuran',
      'Belum ada catatan makan',
      'Belum ada jadwal obat',
    ]);
  });

  test('Today actions come only from real state', () {
    final now = DateTime(2026, 11, 10, 13);
    final actions = buildTodayActions(
      now: now,
      mealCount: 0,
      medication: [
        (
          name: 'Obat pagi',
          localTime: '07:00',
          at: DateTime(2026, 11, 10, 7),
          status: 'unknown',
        ),
        (
          name: 'Obat malam',
          localTime: '20:00',
          at: DateTime(2026, 11, 10, 20),
          status: 'unknown',
        ),
        (
          name: 'Obat siang',
          localTime: '12:00',
          at: DateTime(2026, 11, 10, 12),
          status: 'taken',
        ),
      ],
      goals: [
        (title: 'Jalan kaki', manual: true, ratio: 0.5),
        (title: 'Menit aktif', manual: false, ratio: 0.1),
      ],
    );
    expect(actions.map((a) => a.title), [
      'Konfirmasi Obat pagi',
      'Catat makanan',
      'Check-in: Jalan kaki',
    ]);
    expect(
      buildTodayActions(
        now: DateTime(2026, 11, 10, 9),
        mealCount: 0,
        medication: const [],
        goals: [(title: 'Selesai', manual: true, ratio: 1)],
      ),
      isEmpty,
    );
  });

  testWidgets(
    'Nutrition snapshot: no targets, partial and unknown stay explicit',
    (tester) async {
      await initializeDateFormatting('id_ID');
      final day = NutritionDay(2, {
        'calories': const NutrientTotal(279.4, 'COMPLETE', 2, 2),
        'carbohydrates': const NutrientTotal(54.1, 'COMPLETE', 2, 2),
        'protein': const NutrientTotal(9.6, 'COMPLETE', 2, 2),
        'fat': const NutrientTotal(null, 'UNKNOWN', 0, 2),
        'fiber': const NutrientTotal(2.6, 'PARTIAL', 1, 2),
      }, const []);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NutritionSnapshotCard(nutrition: day)),
        ),
      );
      expect(find.text('279'), findsOneWidget);
      expect(find.text('kkal tercatat'), findsOneWidget);
      expect(find.text('tidak diketahui'), findsOneWidget);
      expect(find.text('2,6 g · sebagian'), findsOneWidget);
      expect(
        find.text('Serat hanya dari 1 dari 2 item; sisanya tidak diketahui.'),
        findsOneWidget,
      );
      expect(find.textContaining('Tanpa target'), findsOneWidget);
      expect(
        find.textContaining(RegExp('melebihi|batas harian|terlalu banyak')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Companion insight shows the first non-medication card and hides when there is none',
    (tester) async {
      await initializeDateFormatting('id_ID');
      Future<void> pump(bool cards) => tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            statisticsProvider.overrideWith(
              (ref, days) async =>
                  Statistics.fromJson(_json(days, cards: cards)),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: CompanionInsightCard()),
          ),
        ),
      );
      await pump(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Sedikit wawasan hari ini'), findsOneWidget);
      expect(find.text('80 menit tercatat'), findsOneWidget);
      expect(find.text('Lihat pola'), findsOneWidget);
      expect(find.text('Tanya beOkay'), findsNothing);
      await pump(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Sedikit wawasan hari ini'), findsNothing);
    },
  );
}
