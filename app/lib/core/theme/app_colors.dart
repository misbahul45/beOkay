import 'package:flutter/painting.dart';

/// Palette derived from the beOkay logo (deep teal wordmark, emerald "Okay", leaf green, aqua ring).
/// UI Refresh v3: one deep-teal brand colour for actions, a mint-tinted canvas, and a distinct
/// hue per health domain. Domain colour never carries meaning alone: every domain also has an icon and label.
abstract final class AppColors {
  // Brand
  static const Color brand = Color(
    0xFF0B4F5E,
  ); // deep teal — buttons, nav (white text 9.9:1)
  static const Color emerald = Color(
    0xFF0BA66B,
  ); // "Okay" green — positive accents
  static const Color leaf = Color(0xFF6CBF2A);
  static const Color aqua = Color(0xFF5ED3E6);

  // Surfaces
  static const Color background = Color(0xFFF1F8F6); // mint-tinted canvas
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFE6F1EE);
  static const Color accent = Color(0xFFD8F0E7); // default icon tint (mint)
  static const Color border = Color(0xFFD9E7E3);
  static const Color overlay = Color(
    0xFF9FC4BE,
  ); // inactive nav icons/labels on brand

  // Text and actions
  static const Color primary = brand;
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF10252B);
  static const Color textSecondary = Color(0xFF47616A); // 6.3:1 on background
  static const Color decorative = Color(0xFF7C9A9F);
  static const Color disabled = Color(0xFF9FC4BE);

  // Semantic
  static const Color errorBackground = Color(0xFFF7E8E6);
  static const Color errorForeground = Color(0xFF8A3B35);
  static const Color warningBackground = Color(0xFFFBF3E0);
  static const Color warningForeground = Color(0xFF7A5710);
  static const Color infoBackground = Color(0xFFD8F0E7);
  static const Color infoForeground = Color(0xFF0B4F5E);
  static const Color focus = brand;

  // Domains: tint (icon circle / chart fill) + ink (icon / chart stroke)
  static const Color glucoseTint = Color(0xFFBFE8F6);
  static const Color glucoseInk = Color(0xFF0A6E8A);
  static const Color mealTint = Color(0xFFD5EDB4);
  static const Color mealInk = Color(0xFF3F7D12);
  static const Color activityTint = Color(0xFFB8ECD3);
  static const Color activityInk = Color(0xFF0A7A4D);
  static const Color medicationTint = Color(0xFFDCD2F7);
  static const Color medicationInk = Color(0xFF5A45A8);
  static const Color goalTint = Color(0xFFFADB9E);
  static const Color goalInk = Color(0xFF8A5A00);
}
