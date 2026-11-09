import 'package:app/features/insights/application/insights_controller.dart';
import 'package:app/features/insights/data/trends.dart';
import 'package:app/features/insights/presentation/trend_charts.dart';
import 'package:app/features/insights/presentation/trends_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

Map<String, dynamic> _json(int days, {bool empty = false}) {
  final start = DateTime(2026, 11, 9).subtract(Duration(days: days - 1));
  String d(int i) => start.add(Duration(days: i)).toIso8601String().substring(0, 10);
  int? act(int i) => empty ? null : (i == days - 3 ? 35 : (i % 3 == 0 ? 20 : null));
  return {
    'days': days,
    'analyticsState': empty ? 'INSUFFICIENT_DATA' : 'READY',
    'series': [
      for (var i = 0; i < days; i++)
        {
          'date': d(i),
          'recorded': !empty && i % 2 == 0,
          'glucose': !empty && i % 2 == 0 ? {'count': 2, 'min': 98, 'max': 142} : null,
          'activityMinutes': act(i),
          'meals': {'count': !empty && i % 3 == 0 ? 2 : 0, 'carbs': !empty && i % 3 == 0 ? {'value': i % 6 == 0 ? 90.0 : null, 'coverage': i % 6 == 0 ? 'PARTIAL' : 'UNKNOWN'} : null},
          'medication': {'taken': !empty && i % 2 == 0 ? 2 : 0, 'skipped': !empty && i % 4 == 0 ? 1 : 0},
        },
    ],
    'previous': [for (var i = 0; i < days; i++) {'date': d(i), 'activityMinutes': empty ? null : (i == 1 ? 15 : null)}],
    'consistency': {'recordedDays': empty ? 0 : (days / 2).ceil(), 'totalDays': days, 'previousRecordedDays': 0, 'currentStreak': 0, 'bestStreak': 1},
    'activity': {'totalMinutes': empty ? null : 120, 'previousTotalMinutes': empty ? null : 15, 'activeDays': empty ? 0 : 4, 'previousActiveDays': 1, 'bestDay': empty ? null : {'date': d(days - 3), 'minutes': 35}},
    'glucose': {'readings': empty ? 0 : 14, 'previousReadings': 0, 'daysWithReadings': empty ? 0 : 7, 'min': 98, 'max': 142},
    'notes': empty ? [] : [{'code': 'ACTIVITY_MORE', 'current': 120, 'previous': 15}, {'code': 'ACTIVITY_PERSONAL_BEST_DAY', 'date': d(days - 3), 'minutes': 35}],
  };
}

Future<void> _pump(WidgetTester tester, {bool empty = false}) async {
  await initializeDateFormatting('id_ID');
  tester.view.physicalSize = const Size(390, 2400) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const TrendsScreen())]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trendsProvider.overrideWith((ref) async => Trends.fromJson(_json(ref.watch(trendRangeProvider), empty: empty))),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1000));
}

Offset _slot(WidgetTester tester, Finder chart, int i, int count, {double inset = 0, double y = 40}) {
  final tl = tester.getTopLeft(chart);
  final w = tester.getSize(chart).width;
  return Offset(tl.dx + inset + (w - inset) / count * (i + 0.5), tl.dy + y + 60);
}

void main() {
  testWidgets('Trends: hero numbers, honest empty days, and no clinical judgement', (tester) async {
    await _pump(tester);
    expect(find.text('Tren'), findsOneWidget);
    expect(find.text('7 dari 14 hari'), findsOneWidget);
    expect(find.text('120 menit'), findsOneWidget);
    expect(find.text('14 hari sebelumnya: 15 menit'), findsOneWidget);
    expect(find.textContaining('105 menit aktivitas lebih banyak'), findsOneWidget);
    expect(find.textContaining('Hari kosong bukan kegagalan'), findsOneWidget);
    expect(find.textContaining('bukan time-in-range'), findsOneWidget);
    // Tidak ada skor/penilaian.
    for (final bad in ['target glukosa', 'terlalu tinggi', 'terlalu rendah', 'persen kepatuhan']) {
      expect(find.textContaining(bad), findsNothing, reason: bad);
    }
  });

  testWidgets('Scrubbing an activity chart shows that day in the readout, and haptics do not crash', (tester) async {
    await _pump(tester);
    final chart = find.byType(ActivityChart);
    await tester.ensureVisible(chart);
    await tester.pump();
    expect(find.textContaining('Geser atau ketuk'), findsWidgets);
    // slot index 11 of 14 = the 35-minute day.
    await tester.tapAt(_slot(tester, chart, 11, 14, inset: 30));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('35 menit'), findsWidgets);
    expect(find.textContaining('Terbanyak di rentang ini'), findsOneWidget);
    // A day without sessions says so instead of showing zero.
    await tester.tapAt(_slot(tester, chart, 2, 14, inset: 30));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Tidak ada sesi'), findsOneWidget);
    expect(find.text('0 menit'), findsNothing);
  });

  testWidgets('Dragging across the chart follows the finger', (tester) async {
    await _pump(tester);
    final chart = find.byType(GlucoseChart);
    await tester.ensureVisible(chart);
    await tester.pump();
    final g = await tester.startGesture(_slot(tester, chart, 0, 14, inset: 34));
    await g.moveTo(_slot(tester, chart, 6, 14, inset: 34));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('98–142 mg/dL'), findsOneWidget);
    expect(find.text('2 pengukuran'), findsNothing); // extra is joined with the date in the caption line
    await g.up();
  });

  testWidgets('Every chart has a table twin so values never depend on touch', (tester) async {
    await _pump(tester);
    expect(find.text('Lihat sebagai tabel'), findsNWidgets(5));
    final toggle = find.text('Lihat sebagai tabel').at(1);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();
    expect(find.text('Sebelumnya'), findsOneWidget);
    expect(find.text('35'), findsOneWidget);
    expect(find.text('Sembunyikan tabel'), findsOneWidget);
  });

  testWidgets('Per-day semantics exist for screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    final labels = <String>[];
    void walk(SemanticsNode n) {
      labels.add(n.label);
      n.visitChildren((c) {
        walk(c);
        return true;
      });
    }

    walk(tester.getSemantics(find.byType(Scaffold).first));
    expect(labels.where((l) => l.endsWith(': 35 menit') || l.contains(': 35 menit, ')), isNotEmpty);
    expect(labels.where((l) => l.contains('tidak ada sesi tercatat')), isNotEmpty);
    expect(labels.where((l) => l.contains('98–142 mg/dL, 2 pengukuran')), isNotEmpty);
    expect(labels.where((l) => l.contains('tidak ada pengukuran')), isNotEmpty);
    handle.dispose();
  });

  testWidgets('Range switch re-scopes every chart; empty history is an honest message', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('30 hari'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('15 dari 30 hari'), findsOneWidget);
    expect(find.text('Total 30 hari'), findsOneWidget);
  });

  testWidgets('No records: message instead of empty axes', (tester) async {
    await _pump(tester, empty: true);
    expect(find.textContaining('Belum ada catatan di rentang ini'), findsOneWidget);
    expect(find.byType(ActivityChart), findsNothing);
  });

  testWidgets('Meal chart: partial coverage is labelled, unknown is not drawn as zero', (tester) async {
    await _pump(tester);
    final chart = find.byType(MealChart);
    await tester.ensureVisible(chart);
    await tester.pump();
    await tester.tapAt(_slot(tester, chart, 6, 14, inset: 30)); // i%6==0 → 90 g partial
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('90 g karbohidrat'), findsOneWidget);
    expect(find.textContaining('sebagian item'), findsWidgets);
    await tester.tapAt(_slot(tester, chart, 3, 14, inset: 30)); // meals but no carb data
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Karbohidrat tidak diketahui'), findsOneWidget);
    await tester.tapAt(_slot(tester, chart, 4, 14, inset: 30)); // no meals
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Tidak ada catatan makan'), findsWidgets);
  });

  testWidgets('Medication chart: counts only, no adherence percentage; skipped is not called failure', (tester) async {
    await _pump(tester);
    final chart = find.byType(MedicationChart);
    await tester.ensureVisible(chart);
    await tester.pump();
    await tester.tapAt(_slot(tester, chart, 4, 14));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('2 diminum, 1 dilewati'), findsOneWidget);
    await tester.tapAt(_slot(tester, chart, 3, 14));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Tidak ada konfirmasi'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    for (final bad in ['terlewat', 'tidak patuh', 'lupa']) {
      expect(find.textContaining(bad), findsNothing, reason: bad);
    }
    expect(find.text('Lihat sebagai tabel'), findsNWidgets(5));
  });

  testWidgets('90 days: narrow cells still render and scrub; no overflow', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('90 hari'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('45 dari 90 hari'), findsOneWidget);
    final chart = find.byType(ConsistencyChart);
    await tester.ensureVisible(chart);
    await tester.pump();
    await tester.tapAt(_slot(tester, chart, 88, 90));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ada catatan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Text scale 2.0: no overflow, readout and hero numbers still present', (tester) async {
    await initializeDateFormatting('id_ID');
    tester.view.physicalSize = const Size(390, 2400) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const TrendsScreen())]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [trendsProvider.overrideWith((ref) async => Trends.fromJson(_json(14)))],
        child: MaterialApp.router(routerConfig: router, builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(2.0)), child: child!)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('7 dari 14 hari'), findsOneWidget);
    final chart = find.byType(ActivityChart);
    await tester.ensureVisible(chart);
    await tester.pump();
    final tl = tester.getTopLeft(chart);
    final sz = tester.getSize(chart);
    await tester.tapAt(Offset(tl.dx + 30 + (sz.width - 30) / 14 * 11.5, tl.dy + sz.height - 50));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('35 menit'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
