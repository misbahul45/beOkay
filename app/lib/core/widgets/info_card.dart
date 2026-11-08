import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

enum InfoTone { info, warning, error, neutral }

class InfoCard extends StatelessWidget {
  const InfoCard({
    super.key,
    required this.text,
    this.icon,
    this.tone = InfoTone.info,
    this.title,
    this.action,
  });

  final String text;
  final String? title;
  final IconData? icon;
  final InfoTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, defaultIcon) = switch (tone) {
      InfoTone.info => (
        AppColors.infoBackground,
        AppColors.infoForeground,
        Icons.info_outline,
      ),
      InfoTone.warning => (
        AppColors.warningBackground,
        AppColors.warningForeground,
        Icons.warning_amber_rounded,
      ),
      InfoTone.error => (
        AppColors.errorBackground,
        AppColors.errorForeground,
        Icons.error_outline,
      ),
      InfoTone.neutral => (
        AppColors.surfaceMuted,
        AppColors.textPrimary,
        Icons.info_outline,
      ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.input + 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? defaultIcon, size: 20, color: foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: AppTypography.secondaryStrong.copyWith(
                      color: foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  text,
                  style: AppTypography.secondary.copyWith(color: foreground),
                ),
                if (action != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  action!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.icon,
    this.tone = InfoTone.neutral,
  });

  final String label;
  final IconData? icon;
  final InfoTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      InfoTone.info => (AppColors.infoBackground, AppColors.infoForeground),
      InfoTone.warning => (
        AppColors.warningBackground,
        AppColors.warningForeground,
      ),
      InfoTone.error => (AppColors.errorBackground, AppColors.errorForeground),
      InfoTone.neutral => (AppColors.surfaceMuted, AppColors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: AppTypography.caption.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: InfoCard(text: message, tone: InfoTone.error),
    );
  }
}
