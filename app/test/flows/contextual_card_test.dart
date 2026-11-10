import 'package:app/features/insights/application/insights_controller.dart';
import 'package:app/features/insights/data/contextual_insights.dart';
import 'package:app/features/insights/presentation/contextual_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(ContextualInsights? data) => ProviderScope(
  overrides: [contextualInsightsProvider.overrideWith((ref) async => data)],
  child: const MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: ContextualCard())),
  ),
);

void main() {
  testWidgets('Shows up to the observations the server sent, as plain notes', (
    tester,
  ) async {
    final data = ContextualInsights.fromJson({
      'items': [
        {
          'code': 'MEDICATION_UNCONFIRMED',
          'domain': 'medication',
          'title': 'Jadwal obat belum dikonfirmasi',
          'body': '2 jadwal hari ini sudah lewat dan belum kamu konfirmasi.',
        },
        {
          'code': 'LOGGING_STREAK',
          'domain': 'general',
          'title': '4 hari berturut-turut mencatat',
          'body': 'Kamu konsisten mencatat.',
        },
      ],
      'suppressed': 1,
    });
    await tester.pumpWidget(_app(data));
    await tester.pumpAndSettle();
    expect(find.text('Catatan untukmu'), findsOneWidget);
    expect(find.text('Jadwal obat belum dikonfirmasi'), findsOneWidget);
    expect(find.text('4 hari berturut-turut mencatat'), findsOneWidget);
  });

  testWidgets(
    'Renders nothing when there are no observations, or when the request failed',
    (tester) async {
      await tester.pumpWidget(
        _app(
          ContextualInsights.fromJson({'items': <dynamic>[], 'suppressed': 0}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Catatan untukmu'), findsNothing);
      await tester.pumpWidget(_app(null));
      await tester.pumpAndSettle();
      expect(find.text('Catatan untukmu'), findsNothing);
    },
  );
}
