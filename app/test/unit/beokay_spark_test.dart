import 'dart:ui' show PictureRecorder;

import 'package:app/core/widgets/beokay_spark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(body: Center(child: child)),
  ),
);

SparkPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(BeOkaySpark),
        matching: find.byType(CustomPaint),
      ),
    )
    .map((p) => p.painter)
    .whereType<SparkPainter>()
    .single;

void main() {
  testWidgets('Ambient motion runs a few cycles and then rests', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const BeOkaySpark()));
    await tester.pump(const Duration(milliseconds: 650));
    expect(_painter(tester).t, greaterThan(0));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Reduced motion draws a still pose and schedules no frames', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const BeOkaySpark(state: SparkState.searching), reduceMotion: true),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(_painter(tester).t, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Busy states keep moving while the work lasts', (tester) async {
    await tester.pumpWidget(
      _host(const BeOkaySpark(state: SparkState.thinking)),
    );
    await tester.pump(const Duration(seconds: 20));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(_host(const BeOkaySpark(state: SparkState.idle)));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Error and paused states never animate', (tester) async {
    for (final state in [SparkState.error, SparkState.paused]) {
      await tester.pumpWidget(_host(BeOkaySpark(state: state)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(_painter(tester).t, 0, reason: '$state');
      expect(tester.binding.hasScheduledFrame, isFalse, reason: '$state');
    }
  });

  testWidgets('Celebration plays a short burst once and then settles', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const BeOkaySpark(state: SparkState.idle)));
    await tester.pumpWidget(
      _host(const BeOkaySpark(state: SparkState.celebrating)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(_painter(tester).burst, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Decorative by default; announced only with a label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(const BeOkaySpark()));
    expect(find.bySemanticsLabel('beOkay'), findsNothing);
    await tester.pumpWidget(
      _host(const BeOkaySpark(semanticLabel: 'beOkay sedang mencari')),
    );
    expect(find.bySemanticsLabel('beOkay sedang mencari'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('Small sizes drop the face so the silhouette stays legible', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const BeOkaySpark(size: 28)));
    expect(_painter(tester).showFace, isFalse);
    await tester.pumpWidget(_host(const BeOkaySpark(size: 48)));
    expect(_painter(tester).showFace, isTrue);
  });

  test('Every state paints without throwing at several sizes', () {
    for (final state in SparkState.values) {
      for (final size in [28.0, 64.0, 120.0]) {
        final recorder = PictureRecorder();
        SparkPainter(
          state: state,
          t: 0.37,
          burst: 0.4,
        ).paint(Canvas(recorder), Size.square(size));
        recorder.endRecording().dispose();
      }
    }
  });
}
