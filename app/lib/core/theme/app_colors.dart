import 'dart:ui' show Brightness;

import 'package:flutter/painting.dart';

class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.brand,
    required this.brandTint,
    required this.leaf,
    required this.aqua,
    required this.sparkAmber,
    required this.sparkCoral,
    required this.sparkCore,
    required this.sparkEye,
    required this.cream,
    required this.peach,
    required this.lavender,
    required this.softBlue,
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.overlay,
    required this.onPrimary,
    required this.textPrimary,
    required this.textSecondary,
    required this.decorative,
    required this.disabled,
    required this.errorBackground,
    required this.errorForeground,
    required this.warningBackground,
    required this.warningForeground,
    required this.infoForeground,
    required this.glucoseSolid,
    required this.glucoseInk,
    required this.mealSolid,
    required this.mealInk,
    required this.activitySolid,
    required this.activityInk,
    required this.medicationSolid,
    required this.medicationInk,
    required this.goalSolid,
    required this.goalInk,
    required this.shadow,
  });

  final Brightness brightness;
  final Color brand, brandTint, leaf, aqua;
  final Color sparkAmber, sparkCoral, sparkCore, sparkEye;
  final Color cream, peach, lavender, softBlue;
  final Color background, surface, surfaceMuted, border, overlay;
  final Color onPrimary, textPrimary, textSecondary, decorative, disabled;
  final Color errorBackground, errorForeground;
  final Color warningBackground, warningForeground, infoForeground;
  final Color glucoseSolid, glucoseInk, mealSolid, mealInk;
  final Color activitySolid, activityInk, medicationSolid, medicationInk;
  final Color goalSolid, goalInk, shadow;

  AppPalette highContrast() => AppPalette(
    brightness: brightness,
    brand: brand,
    brandTint: brandTint,
    leaf: leaf,
    aqua: aqua,
    sparkAmber: sparkAmber,
    sparkCoral: sparkCoral,
    sparkCore: sparkCore,
    sparkEye: sparkEye,
    cream: cream,
    peach: peach,
    lavender: lavender,
    softBlue: softBlue,
    background: background,
    surface: surface,
    surfaceMuted: surfaceMuted,
    border: textSecondary,
    overlay: overlay,
    onPrimary: onPrimary,
    textPrimary: textPrimary,
    textSecondary: textPrimary,
    decorative: textSecondary,
    disabled: textSecondary,
    errorBackground: errorBackground,
    errorForeground: errorForeground,
    warningBackground: warningBackground,
    warningForeground: warningForeground,
    infoForeground: infoForeground,
    glucoseSolid: glucoseSolid,
    glucoseInk: glucoseInk,
    mealSolid: mealSolid,
    mealInk: mealInk,
    activitySolid: activitySolid,
    activityInk: activityInk,
    medicationSolid: medicationSolid,
    medicationInk: medicationInk,
    goalSolid: goalSolid,
    goalInk: goalInk,
    shadow: shadow,
  );

  static const light = AppPalette(
    brightness: Brightness.light,
    brand: Color(0xFF16796F),
    brandTint: Color(0xFFDDF4E8),
    leaf: Color(0xFF46923A),
    aqua: Color(0xFF5ED3E6),
    sparkAmber: Color(0xFFEBAA43),
    sparkCoral: Color(0xFFF17D64),
    sparkCore: Color(0xFFFFF6E3),
    sparkEye: Color(0xFF3B2A1E),
    cream: Color(0xFFFFF1D1),
    peach: Color(0xFFFFE9E2),
    lavender: Color(0xFFF0EBFA),
    softBlue: Color(0xFFE6EFFF),
    background: Color(0xFFF7F7F4),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEEF2EF),
    border: Color(0xFFE4E9E7),
    overlay: Color(0xFF8A9AA0),
    onPrimary: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF1E292B),
    textSecondary: Color(0xFF5C6B73),
    decorative: Color(0xFF7C8C92),
    disabled: Color(0xFFB4C2C0),
    errorBackground: Color(0xFFF7E8E6),
    errorForeground: Color(0xFF8A3B35),
    warningBackground: Color(0xFFFBF3E0),
    warningForeground: Color(0xFF7A5710),
    infoForeground: Color(0xFF145F57),
    glucoseSolid: Color(0xFF4777D4),
    glucoseInk: Color(0xFF2F63C9),
    mealSolid: Color(0xFF46923A),
    mealInk: Color(0xFF3A742C),
    activitySolid: Color(0xFFDC5536),
    activityInk: Color(0xFFC23A1B),
    medicationSolid: Color(0xFF927CC8),
    medicationInk: Color(0xFF6F54B5),
    goalSolid: Color(0xFFB87A12),
    goalInk: Color(0xFF8F5D0E),
    shadow: Color(0x141E292B),
  );

  static const dark = AppPalette(
    brightness: Brightness.dark,
    brand: Color(0xFF5CC9BC),
    brandTint: Color(0xFF17383A),
    leaf: Color(0xFF8FD08A),
    aqua: Color(0xFF5ED3E6),
    sparkAmber: Color(0xFFEBAA43),
    sparkCoral: Color(0xFFF17D64),
    sparkCore: Color(0xFFFFF6E3),
    sparkEye: Color(0xFF3B2A1E),
    cream: Color(0xFF3A2F1A),
    peach: Color(0xFF3A2420),
    lavender: Color(0xFF2A2440),
    softBlue: Color(0xFF1D2B45),
    background: Color(0xFF0F1719),
    surface: Color(0xFF172124),
    surfaceMuted: Color(0xFF1F2B2E),
    border: Color(0xFF2A373B),
    overlay: Color(0xFF7E9095),
    onPrimary: Color(0xFF0F1719),
    textPrimary: Color(0xFFEEF3F1),
    textSecondary: Color(0xFFA3B3B8),
    decorative: Color(0xFF7E9095),
    disabled: Color(0xFF3C4B4F),
    errorBackground: Color(0xFF3E2222),
    errorForeground: Color(0xFFF2A9A1),
    warningBackground: Color(0xFF3A3020),
    warningForeground: Color(0xFFF0CF8A),
    infoForeground: Color(0xFF9FE3DA),
    glucoseSolid: Color(0xFF8FB2F5),
    glucoseInk: Color(0xFF8FB2F5),
    mealSolid: Color(0xFF8FD08A),
    mealInk: Color(0xFF8FD08A),
    activitySolid: Color(0xFFF6A08C),
    activityInk: Color(0xFFF6A08C),
    medicationSolid: Color(0xFFB7A6E6),
    medicationInk: Color(0xFFB7A6E6),
    goalSolid: Color(0xFFF0BE6A),
    goalInk: Color(0xFFF0BE6A),
    shadow: Color(0x66000000),
  );
}

abstract final class AppColors {
  static AppPalette _p = AppPalette.light;

  static AppPalette get palette => _p;
  static Brightness get brightness => _p.brightness;
  static void use(Brightness brightness, {bool highContrast = false}) {
    final base = brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    _p = highContrast ? base.highContrast() : base;
  }

  static Color get brand => _p.brand;
  static Color get brandTint => _p.brandTint;
  static Color get emerald => _p.brand;
  static Color get leaf => _p.leaf;
  static Color get aqua => _p.aqua;

  static Color get sparkAmber => _p.sparkAmber;
  static Color get sparkCoral => _p.sparkCoral;
  static Color get sparkCore => _p.sparkCore;
  static Color get sparkEye => _p.sparkEye;
  static Color get cream => _p.cream;
  static Color get peach => _p.peach;
  static Color get lavender => _p.lavender;
  static Color get softBlue => _p.softBlue;

  static Color get background => _p.background;
  static Color get surface => _p.surface;
  static Color get surfaceMuted => _p.surfaceMuted;
  static Color get accent => _p.brandTint;
  static Color get border => _p.border;
  static Color get overlay => _p.overlay;
  static Color get shadow => _p.shadow;

  static Color get primary => _p.brand;
  static Color get onPrimary => _p.onPrimary;
  static Color get textPrimary => _p.textPrimary;
  static Color get textSecondary => _p.textSecondary;
  static Color get decorative => _p.decorative;
  static Color get disabled => _p.disabled;

  static Color get errorBackground => _p.errorBackground;
  static Color get errorForeground => _p.errorForeground;
  static Color get warningBackground => _p.warningBackground;
  static Color get warningForeground => _p.warningForeground;
  static Color get infoBackground => _p.brandTint;
  static Color get infoForeground => _p.infoForeground;
  static Color get focus => _p.brand;

  static Color get glucoseTint => _p.softBlue;
  static Color get glucoseSolid => _p.glucoseSolid;
  static Color get glucoseInk => _p.glucoseInk;
  static Color get mealTint => _p.brandTint;
  static Color get mealSolid => _p.mealSolid;
  static Color get mealInk => _p.mealInk;
  static Color get activityTint => _p.peach;
  static Color get activitySolid => _p.activitySolid;
  static Color get activityInk => _p.activityInk;
  static Color get medicationTint => _p.lavender;
  static Color get medicationSolid => _p.medicationSolid;
  static Color get medicationInk => _p.medicationInk;
  static Color get goalTint => _p.cream;
  static Color get goalSolid => _p.goalSolid;
  static Color get goalInk => _p.goalInk;
}
