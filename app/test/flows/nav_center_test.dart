import 'dart:ui' show Tristate;

import 'package:app/core/widgets/pill_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const items = [
    NavItem(
      label: 'Beranda',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
    ),
    NavItem(
      label: 'Catatan',
      icon: Icons.edit_note_outlined,
      selectedIcon: Icons.edit_note,
    ),
    NavItem(
      label: 'Asisten',
      icon: Icons.auto_awesome_outlined,
      selectedIcon: Icons.auto_awesome,
    ),
    NavItem(
      label: 'Wawasan',
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights,
    ),
  ];

  Future<(List<int>, List<String>)> pump(
    WidgetTester tester, {
    int? current = 0,
    double textScale = 1,
  }) async {
    final taps = <int>[];
    final actions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          bottomNavigationBar: PillNavBar(
            items: items,
            currentIndex: current,
            onTap: taps.add,
            centerAction: NavCenterAction(
              label: 'Catat',
              onPressed: () => actions.add('catat'),
            ),
          ),
        ),
      ),
    );
    return (taps, actions);
  }

  testWidgets(
    'Center + sits between Catatan and Asisten and is a tappable button, not a destination',
    (tester) async {
      final (taps, actions) = await pump(tester);
      final plus = find.byIcon(Icons.add_rounded);
      expect(plus, findsOneWidget);
      final x = tester.getCenter(plus).dx;
      expect(
        x,
        closeTo(tester.getSize(find.byType(Scaffold)).width / 2, 2),
      ); // centered
      expect(tester.getCenter(find.text('Catatan')).dx, lessThan(x));
      expect(tester.getCenter(find.text('Asisten')).dx, greaterThan(x));
      await tester.tap(plus);
      expect(actions, ['catat']);
      expect(taps, isEmpty);
      await tester.tap(find.text('Asisten'));
      await tester.tap(find.text('Wawasan'));
      expect(taps, [2, 3]);
    },
  );

  testWidgets('The center button is announced as a button labelled Catat', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    final node = tester.getSemantics(find.bySemanticsLabel('Catat'));
    expect(node.label, 'Catat');
    expect(node.flagsCollection.isButton, isTrue);
    handle.dispose();
  });

  testWidgets(
    'Without a current destination no item is announced as selected',
    (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, current: null);
      for (final label in ['Beranda', 'Catatan', 'Asisten', 'Wawasan']) {
        final node = tester.getSemantics(find.bySemanticsLabel(label));
        expect(
          node.flagsCollection.isSelected,
          isNot(Tristate.isTrue),
          reason: label,
        );
      }
      handle.dispose();
    },
  );

  testWidgets(
    'At 2x text the labels stay whole (scaled down, not ellipsized)',
    (tester) async {
      await pump(tester, textScale: 2);
      expect(tester.takeException(), isNull);
      for (final label in ['Beranda', 'Catatan', 'Asisten', 'Wawasan']) {
        final text = tester.widget<Text>(find.text(label));
        expect(text.overflow, isNot(TextOverflow.ellipsis), reason: label);
        expect(find.text(label), findsOneWidget);
      }
    },
  );
}
