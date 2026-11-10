import 'package:app/features/goals/application/goals_controller.dart';
import 'package:app/features/goals/data/goals_repository.dart';
import 'package:app/features/goals/presentation/goals_screen.dart';
import 'package:app/features/medication/application/medication_controller.dart';
import 'package:app/features/medication/data/medication_repository.dart';
import 'package:app/features/medication/presentation/medication_screen.dart';
import 'package:app/features/medication/presentation/medication_history_screen.dart';
import 'package:app/features/medication/presentation/medication_form_screen.dart';
import 'package:app/features/goals/presentation/goal_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _app(Widget home, List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp.router(
    routerConfig: GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => home)],
    ),
  ),
);

MedicationToday _today(List<Map<String, dynamic>> items) =>
    MedicationToday.fromJson({
      'date': '2026-11-09',
      'scheduled': items.length,
      'taken': items.where((i) => i['status'] == 'taken').length,
      'skipped': 0,
      'unknown': items.where((i) => i['status'] == 'unknown').length,
      'items': items,
    });

Map<String, dynamic> _occ(String status) => {
  'regimenId': 'r1',
  'scheduleId': 's1',
  'name': 'Obat uji',
  'strength': '500 mg',
  'localTime': '08:00',
  'scheduledAt': '2026-11-09T01:00:00.000Z',
  'status': status,
  'intakeId': status == 'unknown' ? null : 'i1',
  'intakeVersion': status == 'unknown' ? null : 1,
};

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));
  testWidgets(
    'Medication never shows an unconfirmed dose as taken, and offers explicit actions',
    (tester) async {
      await tester.pumpWidget(
        _app(const MedicationScreen(), [
          medicationTodayProvider.overrideWith(
            (ref) async => _today([_occ('unknown')]),
          ),
          medicationListProvider.overrideWith((ref) async => <Regimen>[]),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Belum dikonfirmasi'), findsOneWidget);
      expect(find.text('Sudah diminum'), findsOneWidget);
      expect(find.text('Lewati'), findsOneWidget);
      // Status ditampilkan langsung pada item; tidak ada kotak penjelasan di atas daftar.
      expect(find.textContaining('bukan bukti kamu sudah minum'), findsNothing);
      expect(find.text('Belum ada obat'), findsOneWidget);
    },
  );

  testWidgets('A confirmed dose can be undone, and no confirm buttons remain', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const MedicationScreen(), [
        medicationTodayProvider.overrideWith(
          (ref) async => _today([_occ('taken')]),
        ),
        medicationListProvider.overrideWith((ref) async => <Regimen>[]),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sudah diminum'), findsOneWidget); // badge only
    expect(find.text('Batalkan konfirmasi'), findsOneWidget);
    expect(find.text('Lewati'), findsNothing);
  });

  testWidgets('Goals show honest no-record state and no scoring language', (
    tester,
  ) async {
    final goal = Goal.fromJson({
      'id': 'g1',
      'title': 'Jalan sore',
      'goalType': 'activity_minutes',
      'targetValue': 150,
      'period': 'weekly',
      'status': 'active',
      'version': 1,
      'progress': {
        'value': null,
        'targetValue': 150,
        'ratio': null,
        'sourceCount': 0,
        'periodStart': '2026-11-09',
        'periodEnd': '2026-11-16',
      },
    });
    await tester.pumpWidget(
      _app(const GoalsScreen(), [
        goalsListProvider.overrideWith((ref) async => [goal]),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Belum ada catatan pada periode ini.'), findsOneWidget);
    expect(find.text('Jalan sore'), findsOneWidget);
    expect(
      find.textContaining('poin'),
      findsNothing,
    ); // tidak ada bahasa skor pada tujuan
    expect(
      find.text('Check-in'),
      findsNothing,
    ); // derived goals are not checked in by hand
  });

  testWidgets(
    'Intake history lists confirmations and a correction needs a reason',
    (tester) async {
      final regimen = Regimen.fromJson({
        'id': 'r1',
        'name': 'Obat uji',
        'strength': '500 mg',
        'status': 'active',
        'version': 1,
      });
      await tester.pumpWidget(
        _app(MedicationHistoryScreen(regimen: regimen), [
          medicationIntakesProvider('r1').overrideWith(
            (ref) async => [
              IntakeRecord.fromJson({
                'id': 'i1',
                'status': 'taken',
                'eventAt': '2026-11-09T01:00:00.000Z',
                'version': 2,
                'archivedAt': null,
              }),
            ],
          ),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Riwayat konfirmasi'), findsOneWidget);
      expect(find.text('Sudah diminum'), findsOneWidget);
      expect(find.textContaining('dikoreksi'), findsOneWidget);
      await tester.tap(find.text('Koreksi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(find.text('Isi alasan koreksi.'), findsOneWidget);
    },
  );

  testWidgets('Edit forms start from the saved values and require a reason', (
    tester,
  ) async {
    final regimen = Regimen.fromJson({
      'id': 'r1',
      'name': 'Obat uji',
      'strength': '500 mg',
      'dosageForm': 'tablet',
      'status': 'active',
      'version': 3,
    });
    await tester.pumpWidget(
      _app(MedicationFormScreen(initial: regimen), const []),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ubah obat'), findsOneWidget);
    expect(find.text('Obat uji'), findsOneWidget);
    expect(find.text('Jadwal pengingat (opsional)'), findsNothing);
    await tester.tap(find.text('Simpan perubahan'));
    await tester.pumpAndSettle();
    expect(find.text('Isi alasan perubahan.'), findsOneWidget);

    final goal = Goal.fromJson({
      'id': 'g1',
      'title': 'Jalan sore',
      'goalType': 'activity_minutes',
      'targetValue': 150,
      'period': 'weekly',
      'status': 'active',
      'version': 1,
    });
    await tester.pumpWidget(_app(GoalFormScreen(initial: goal), const []));
    await tester.pumpAndSettle();
    expect(find.text('Ubah tujuan'), findsOneWidget);
    expect(find.text('Jalan sore'), findsOneWidget);
    expect(find.text('150'), findsOneWidget);
  });
}
