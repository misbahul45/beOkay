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
      label: 'Wawasan',
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights,
    ),
    NavItem(
      label: 'Profil',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
    ),
  ];

  Future<(List<int>, List<String>)> pump(WidgetTester tester) async {
    final taps = <int>[];
    final actions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: PillNavBar(
            items: items,
            currentIndex: 0,
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
    'Center + sits between Catatan and Wawasan and is a tappable button, not a destination',
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
      expect(tester.getCenter(find.text('Wawasan')).dx, greaterThan(x));
      await tester.tap(plus);
      expect(actions, ['catat']);
      expect(taps, isEmpty);
      await tester.tap(find.text('Wawasan'));
      expect(taps, [2]); // destination indices are unchanged by the center slot
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
}
