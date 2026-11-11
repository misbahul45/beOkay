import 'package:app/features/insights/application/insights_controller.dart';
import 'package:app/features/insights/data/statistics.dart';
import 'package:app/features/insights/presentation/statistics_section.dart';
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

Future<List<int>> _pump(
  WidgetTester tester, {
  bool ready = true,
  bool cards = true,
}) async {
  await initializeDateFormatting('id_ID');
  tester.view.physicalSize = const Size(390, 2600) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final requested = <int>[];
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(
          body: SingleChildScrollView(child: StatisticsSection()),
        ),
      ),
      GoRoute(
        path: '/trends',
        builder: (_, _) => const Scaffold(body: Text('Halaman tren')),
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
  return requested;
}

void main() {
  testWidgets(
    'Statistics: insight card shows evidence, coverage and actions; tiles separate data from insufficient data',
    (tester) async {
      await _pump(tester);
      expect(
        find.text(
          'Durasi aktivitas tercatat lebih rendah dari 7 hari sebelumnya.',
        ),
        findsOneWidget,
      );
      expect(find.text('80 menit · 3 hari aktif'), findsOneWidget);
      expect(find.text('Cakupan: 3 dari 7 hari ada data'), findsOneWidget);
      expect(find.text('Lihat detail'), findsOneWidget);
      expect(find.text('Buat target'), findsOneWidget);
      expect(find.text('Tanya beOkay'), findsOneWidget);
      expect(find.text('−25 menit dari periode sebelumnya'), findsOneWidget);
      expect(find.text('2/7'), findsOneWidget);
      expect(find.text('Perlu minimal 3 hari; ada 2.'), findsOneWidget);
      expect(find.text('Belum cukup data'), findsWidgets);
      expect(
        find.textContaining(RegExp('skor|kepatuhan', caseSensitive: false)),
        findsNothing,
      );
      await tester.tap(find.text('Lihat detail'));
      await tester.pumpAndSettle();
      expect(find.text('Halaman tren'), findsOneWidget);
    },
  );

  testWidgets('Tapping a tile explains how it was computed, with limitations', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('Durasi aktivitas tercatat'));
    await tester.pumpAndSettle();
    expect(find.text('Cara dihitung'), findsOneWidget);
    expect(find.text('Cara hitung activity.total_minutes.'), findsOneWidget);
    expect(find.text('stats-v1'), findsOneWidget);
    expect(find.text('Batasan'), findsOneWidget);
    expect(
      find.textContaining('Batasan activity.total_minutes.'),
      findsOneWidget,
    );
    expect(find.text('Sesi manual dan impor perangkat'), findsOneWidget);
  });

  testWidgets(
    'The period filter drives the request; the table marks missing days',
    (tester) async {
      final requested = await _pump(tester);
      expect(requested.last, 14);
      await tester.tap(find.text('7 hari'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(requested.last, 7);
      await tester.ensureVisible(find.text('Lihat sebagai tabel'));
      await tester.tap(find.text('Lihat sebagai tabel'));
      await tester.pumpAndSettle();
      expect(find.text('–'), findsWidgets);
      expect(find.text('tidak diketahui'), findsOneWidget);
    },
  );

  testWidgets('No records: honest empty state instead of numbers or cards', (
    tester,
  ) async {
    await _pump(tester, ready: false);
    expect(find.text('Belum ada catatan di 14 hari terakhir'), findsOneWidget);
    expect(find.text('Lihat detail'), findsNothing);
  });

  testWidgets('Without strong patterns the section says so', (tester) async {
    await _pump(tester, cards: false);
    expect(
      find.textContaining('Belum ada pola yang cukup kuat'),
      findsOneWidget,
    );
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
      expect(find.text('Lihat pola'), findsOneWidget);
      await pump(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Sedikit wawasan hari ini'), findsNothing);
    },
  );
}
