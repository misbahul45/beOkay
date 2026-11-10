import 'package:app/features/insights/application/insights_controller.dart';
import 'package:app/features/insights/data/daily_insights.dart';
import 'package:app/features/insights/presentation/insights_screen.dart';
import 'package:app/features/timeline/application/timeline_controller.dart';
import 'package:app/features/timeline/data/timeline_models.dart';
import 'package:app/features/timeline/presentation/log_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

Map<String, dynamic> _item(
  String domain,
  String id,
  Map<String, dynamic> extra,
) => {
  'domain': domain,
  'recordId': id,
  'localDate': '2026-11-08',
  'localTime': '07:00',
  ...extra,
};

final _all = [
  _item('meal', 'meal-1', {'category': 'breakfast', 'itemCount': 2}),
  _item('glucose', 'glu-1', {
    'displayValue': 96,
    'displayUnit': 'mg/dL',
    'qualityStatus': 'user_reported',
    'mealContext': 'fasting',
  }),
  _item('activity', 'act-1', {
    'activityType': 'walking',
    'durationMinutes': 30,
    'qualityStatus': 'user_reported',
  }),
];

/// Records each filter the screen asked for and answers like the server: by domain.
class _FakeFeed extends LogFeedController {
  static final requested = <LogFilter>[];
  static List<Map<String, dynamic>> source = _all;

  @override
  Future<LogFeed> build() async {
    final filter = ref.watch(logFilterProvider);
    requested.add(filter);
    final rows = source
        .where(
          (row) => filter.domain == 'all' || row['domain'] == filter.domain,
        )
        .map(TimelineItem.fromJson)
        .toList();
    return LogFeed(items: rows, timezone: 'Asia/Jakarta');
  }
}

Widget _app(Widget home, {List<Override> overrides = const []}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(
        path: '/glucose/:id',
        builder: (_, state) => Scaffold(
          body: Text('Detail glukosa ${state.pathParameters['id']}'),
        ),
      ),
      GoRoute(
        path: '/meals/:id',
        builder: (_, state) => Scaffold(
          body: Text('Detail makanan ${state.pathParameters['id']}'),
        ),
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));
  setUp(() {
    _FakeFeed.requested.clear();
    _FakeFeed.source = _all;
  });

  testWidgets('Log filter chips drive the API query and the visible rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const LogScreen(),
        overrides: [logFeedProvider.overrideWith(_FakeFeed.new)],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sarapan'), findsOneWidget);
    expect(find.text('96 mg/dL'), findsOneWidget);
    expect(find.text('Jalan kaki'), findsOneWidget);

    await tester.tap(find.text('Glukosa'));
    await tester.pumpAndSettle();
    expect(_FakeFeed.requested.last.domain, 'glucose');
    expect(find.text('96 mg/dL'), findsOneWidget);
    expect(find.text('Sarapan'), findsNothing);
    expect(find.text('Jalan kaki'), findsNothing);
  });

  testWidgets('Log row opens the original record', (tester) async {
    await tester.pumpWidget(
      _app(
        const LogScreen(),
        overrides: [logFeedProvider.overrideWith(_FakeFeed.new)],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('96 mg/dL'));
    await tester.pumpAndSettle();
    expect(find.text('Detail glukosa glu-1'), findsOneWidget);
  });

  testWidgets('Log shows an honest empty state with a way out of the filter', (
    tester,
  ) async {
    _FakeFeed.source = [];
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: LogScreen(),
        ),
        overrides: [logFeedProvider.overrideWith(_FakeFeed.new)],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Belum ada catatan'), findsOneWidget);
    expect(find.text('Mulai mencatat'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  Map<String, dynamic> summary({
    int meals = 0,
    int glucose = 0,
    int sessions = 0,
  }) => {
    'date': '2026-11-08',
    'timezone': 'Asia/Jakarta',
    'mealCount': meals,
    'totals': {
      for (final key in [
        'calories',
        'carbohydrates',
        'protein',
        'fat',
        'fiber',
      ])
        key: {
          'value': null,
          'knownItems': 0,
          'totalItems': meals,
          'coverage': 'UNKNOWN',
        },
    },
    'recent': <Map<String, dynamic>>[],
    'freshness': 'CURRENT',
    'computedAt': '2026-11-08T10:00:00Z',
    'glucose': {
      'count': glucose,
      'eligibleCount': glucose,
      'reviewCount': 0,
      'latest': null,
      'mean': null,
      'minimum': null,
      'maximum': null,
      'displayUnit': 'mg/dL',
      'computationVersion': 'v1',
      'computedAt': '2026-11-08T10:00:00Z',
      'analyticsState': 'INSUFFICIENT_DATA',
      'freshness': 'CURRENT',
    },
    'activity': {
      'count': sessions,
      'eligibleCount': sessions,
      'reviewCount': 0,
      'durationMinutes': sessions == 0 ? null : 30,
      'distanceKm': {
        'value': null,
        'knownSessions': 0,
        'totalSessions': sessions,
        'coverage': 'UNKNOWN',
      },
      'steps': {
        'value': null,
        'knownSessions': 0,
        'totalSessions': sessions,
        'coverage': 'UNKNOWN',
      },
      'date': '2026-11-08',
      'startDate': '2026-11-08',
      'endDate': '2026-11-09',
      'timezone': 'Asia/Jakarta',
      'firstDay': null,
      'activeDays': sessions == 0 ? 0 : 1,
      'computedAt': '2026-11-08T10:00:00Z',
      'computationVersion': 'v1',
      'days': <Map<String, dynamic>>[],
    },
  };

  testWidgets(
    'Insights never turns unknown into zero and explains empty days',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final empty = DailyInsights.fromJson(summary());
      await tester.pumpWidget(
        _app(
          const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: InsightsScreen(),
          ),
          overrides: [dailyInsightsProvider.overrideWith((ref) async => empty)],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Belum ada catatan di hari ini'), findsOneWidget);
      expect(find.text('Belum ada pengukuran.'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Insights labels sparse glucose and unknown nutrition as such', (
    tester,
  ) async {
    final data = DailyInsights.fromJson(
      summary(meals: 1, glucose: 1, sessions: 1),
    );
    await tester.pumpWidget(
      _app(
        const InsightsScreen(),
        overrides: [dailyInsightsProvider.overrideWith((ref) async => data)],
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('bukan nol'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining('Statistik ringkasan belum ditampilkan'),
      findsOneWidget,
    );
    expect(find.text('Energi: Belum tersedia'), findsOneWidget);
    expect(find.textContaining('bukan nol'), findsOneWidget);
  });

  // Pixel-level wrapping cannot be asserted here (the test font is monospaced-square); that was checked on a
  // physical device at font scale 2.0. This guards against overflow exceptions at the same size.
  testWidgets('Large text on a narrow screen renders Log without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const scaled = MediaQueryData(textScaler: TextScaler.linear(2));

    await tester.pumpWidget(
      _app(
        const MediaQuery(data: scaled, child: LogScreen()),
        overrides: [logFeedProvider.overrideWith(_FakeFeed.new)],
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Large text on a narrow screen renders Insights badges without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const scaled = MediaQueryData(textScaler: TextScaler.linear(2));
      final data = DailyInsights.fromJson(
        summary(meals: 1, glucose: 1, sessions: 1),
      );
      await tester.pumpWidget(
        _app(
          const MediaQuery(data: scaled, child: InsightsScreen()),
          overrides: [dailyInsightsProvider.overrideWith((ref) async => data)],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Data belum cukup'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
