import 'package:app/core/format/greeting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first name and part of day', () {
    expect(firstName('  Rina Putri '), 'Rina');
    expect(firstName(''), '');
    expect(
      [
        for (final h in [6, 12, 16, 21]) partOfDay(h),
      ],
      ['pagi', 'siang', 'sore', 'malam'],
    );
  });
  test(
    'greeting is friendly, short, and only prompts from facts the app has',
    () {
      final calm = greetingFor(
        now: DateTime(2026, 11, 9, 9),
        name: 'Rina Putri',
      );
      expect(calm.title, 'Halo, Rina! Bagaimana kabarmu pagi ini?');
      expect(calm.detail, isNull);
      expect(
        greetingFor(
          now: DateTime(2026, 11, 9, 9),
          name: '',
        ).title.startsWith('Halo! '),
        isTrue,
      );
    },
  );
  test(
    'meal prompt only in meal hours, medication prompt wins and never claims a dose was missed',
    () {
      expect(
        greetingFor(
          now: DateTime(2026, 11, 9, 13),
          name: 'Rina',
          noMealToday: true,
        ).title,
        'Halo, Rina! Sudah makan siang?',
      );
      expect(
        greetingFor(
          now: DateTime(2026, 11, 9, 8),
          name: 'Rina',
          noMealToday: true,
        ).detail,
        isNull,
      );
      expect(
        greetingFor(
          now: DateTime(2026, 11, 9, 23),
          name: 'Rina',
          noMealToday: true,
        ).detail,
        isNull,
      );
      final med = greetingFor(
        now: DateTime(2026, 11, 9, 13),
        name: 'Rina',
        unconfirmedMedications: 2,
        noMealToday: true,
      );
      expect(med.detail, 'Ada 2 obat yang belum dikonfirmasi.');
      expect(
        med.detail!.contains('lupa') || med.detail!.contains('terlewat'),
        isFalse,
      );
    },
  );
}
