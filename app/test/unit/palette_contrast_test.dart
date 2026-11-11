import 'dart:math' as math;

import 'package:app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _channel(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

double contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final p in [AppPalette.light, AppPalette.dark]) {
    group('${p.brightness.name} palette', () {
      test('text reaches WCAG AA on every surface it is used on', () {
        for (final bg in [
          p.background,
          p.surface,
          p.surfaceMuted,
          p.brandTint,
          p.cream,
          p.peach,
          p.lavender,
          p.softBlue,
        ]) {
          expect(contrast(p.textPrimary, bg), greaterThanOrEqualTo(7));
          expect(contrast(p.textSecondary, bg), greaterThanOrEqualTo(4.5));
        }
      });

      test('domain inks reach 4.5:1 on their tint and on the surface', () {
        final pairs = {
          'glucose': (p.glucoseInk, p.softBlue),
          'meal': (p.mealInk, p.brandTint),
          'activity': (p.activityInk, p.peach),
          'medication': (p.medicationInk, p.lavender),
          'goal': (p.goalInk, p.cream),
        };
        pairs.forEach((name, pair) {
          expect(
            contrast(pair.$1, pair.$2),
            greaterThanOrEqualTo(4.5),
            reason: '$name on tint',
          );
          expect(
            contrast(pair.$1, p.surface),
            greaterThanOrEqualTo(4.5),
            reason: '$name on surface',
          );
        });
      });

      test('actions and status colours stay readable', () {
        expect(contrast(p.onPrimary, p.brand), greaterThanOrEqualTo(4.5));
        expect(contrast(p.brand, p.surface), greaterThanOrEqualTo(4.5));
        expect(
          contrast(p.warningForeground, p.warningBackground),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(p.errorForeground, p.errorBackground),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(p.infoForeground, p.brandTint),
          greaterThanOrEqualTo(4.5),
        );
        for (final solid in [
          p.glucoseSolid,
          p.mealSolid,
          p.activitySolid,
          p.medicationSolid,
          p.goalSolid,
        ]) {
          expect(contrast(solid, p.surface), greaterThanOrEqualTo(3));
        }
      });
    });
  }

  test('switching brightness swaps every token', () {
    AppColors.use(Brightness.dark);
    expect(AppColors.background, AppPalette.dark.background);
    expect(AppColors.textPrimary, AppPalette.dark.textPrimary);
    AppColors.use(Brightness.light);
    expect(AppColors.background, AppPalette.light.background);
  });
}
