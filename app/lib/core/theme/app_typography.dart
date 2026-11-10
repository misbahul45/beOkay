import 'package:flutter/painting.dart';

import 'app_colors.dart';

abstract final class AppTypography {
  static const String family = 'Inter';

  // UI Refresh v2 (design/beOkay-ui.figcraft, page "16 — UI Refresh v2").
  // Smaller than v1 (38/30/24/17/16/14/12.5/11.5) but never below 11sp.
  /// Auth hero only.
  static const TextStyle display = TextStyle(
    fontFamily: family,
    fontSize: 30,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    color: AppColors.textPrimary,
  );

  /// Tab titles and the Beranda greeting.
  static const TextStyle headline = TextStyle(
    fontFamily: family,
    fontSize: 24,
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: AppColors.textPrimary,
  );

  /// Section headings.
  static const TextStyle heading = TextStyle(
    fontFamily: family,
    fontSize: 18,
    height: 1.35,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    color: AppColors.textPrimary,
  );

  /// Card and row titles.
  static const TextStyle title = TextStyle(
    fontFamily: family,
    fontSize: 16,
    height: 1.35,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static const TextStyle body = TextStyle(
    fontFamily: family,
    fontSize: 15,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );
  static const TextStyle bodyStrong = TextStyle(
    fontFamily: family,
    fontSize: 15,
    height: 1.4,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static const TextStyle secondary = TextStyle(
    fontFamily: family,
    fontSize: 13,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );
  static const TextStyle secondaryStrong = TextStyle(
    fontFamily: family,
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static const TextStyle caption = TextStyle(
    fontFamily: family,
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  /// Section labels (uppercase); +0.8 tracking because Inter has a single optical size.
  static const TextStyle overline = TextStyle(
    fontFamily: family,
    fontSize: 11,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    color: AppColors.textSecondary,
  );

  static const TextStyle metricLarge = TextStyle(
    fontFamily: family,
    fontSize: 30,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    color: AppColors.textPrimary,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle metric = TextStyle(
    fontFamily: family,
    fontSize: 18,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: AppColors.textPrimary,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
