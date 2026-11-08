import 'package:app/features/nutrition/data/nutrition_models.dart';
import 'package:app/features/nutrition/presentation/meal_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main(){
  test('Unknown nutrition remains null and partial totals stay labelled',(){
    final value=NutrientTotal.fromJson({'value':null,'coverage':'UNKNOWN','knownItems':0,'totalItems':1});
    expect(value.value,isNull);expect(value.label('kkal'),'Belum tersedia');
    expect(NutrientTotal.fromJson({'value':150,'coverage':'PARTIAL','knownItems':1,'totalItems':2}).label('kkal'),contains('sebagian'));
  });
  testWidgets('Meal form validates required items without submitting', (tester)async{
    await tester.pumpWidget(const ProviderScope(child:MaterialApp(home:MealFormScreen())));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Simpan makanan'));
    await tester.tap(find.text('Simpan makanan'));
    await tester.pumpAndSettle();
    expect(find.text('Tambahkan setidaknya satu makanan.'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
}
