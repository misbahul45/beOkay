import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

abstract final class AppTheme {
  static ThemeData light({required bool reduceMotion}) {
    final scheme = const ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      secondary: AppColors.accent,
      onSecondary: AppColors.textPrimary,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.errorForeground,
      onError: AppColors.onPrimary,
      outline: AppColors.border,
    );
    const transitions = PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      },
    );
    const instant = PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _InstantTransitionsBuilder(),
        TargetPlatform.iOS: _InstantTransitionsBuilder(),
        TargetPlatform.linux: _InstantTransitionsBuilder(),
        TargetPlatform.macOS: _InstantTransitionsBuilder(),
        TargetPlatform.windows: _InstantTransitionsBuilder(),
      },
    );
    return ThemeData(
      useMaterial3: true,
      fontFamily: AppTypography.family,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      splashFactory: reduceMotion
          ? NoSplash.splashFactory
          : InkRipple.splashFactory,
      pageTransitionsTheme: reduceMotion ? instant : transitions,
      dividerColor: AppColors.border,
      textTheme: const TextTheme(
        displayLarge: AppTypography.display,
        headlineMedium: AppTypography.headline,
        headlineSmall: AppTypography.heading,
        titleMedium: AppTypography.title,
        bodyLarge: AppTypography.body,
        bodyMedium: AppTypography.secondary,
        bodySmall: AppTypography.caption,
        labelLarge: AppTypography.bodyStrong,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: AppTypography.title,
      ),
      textButtonTheme: TextButtonThemeData(
        // Text buttons read as buttons (tonal pill), not as loose text.
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          backgroundColor: AppColors.surfaceMuted,
          minimumSize: const Size(AppSpacing.minTouchTarget, 40),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          shape: const StadiumBorder(),
          textStyle: AppTypography.secondaryStrong,
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(side: BorderSide(color: AppColors.border)),
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primary,
        checkmarkColor: AppColors.onPrimary,
        labelStyle: AppTypography.secondaryStrong,
        secondaryLabelStyle: AppTypography.secondaryStrong.copyWith(
          color: AppColors.onPrimary,
        ),
        side: const BorderSide(color: AppColors.border),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primary,
        contentTextStyle: AppTypography.secondaryStrong.copyWith(
          color: AppColors.onPrimary,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.pillRadius),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        titleTextStyle: AppTypography.heading,
        contentTextStyle: AppTypography.secondary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(AppColors.surface),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.overlay,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      focusColor: AppColors.focus,
    );
  }
}

class _InstantTransitionsBuilder extends PageTransitionsBuilder {
  const _InstantTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
