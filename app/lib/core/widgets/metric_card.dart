import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'info_card.dart';

/// Compact domain card used on Today and Insights (UI Refresh v2).
///
/// Row layout: icon · text column · trailing action. The whole card opens the
/// history ([onSecondary]); [onPrimary] is a "+" shortcut to record. [value] is
/// shown only when real data exists; an empty domain passes [emptyMessage]
/// instead so "no data" never looks like a number.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.icon,
    required this.title,
    this.value,
    this.valueCaption,
    this.emptyMessage,
    this.details = const [],
    this.badge,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.footnote,
    this.prominentValue = false,
    this.tint = AppColors.accent,
    this.ink = AppColors.primary,
  });

  final IconData icon;
  final String title;
  final String? value;
  final String? valueCaption;
  final String? emptyMessage;
  final List<String> details;
  final StatusBadge? badge;

  /// Accessible name of the "+" shortcut, e.g. "Catat glukosa".
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  /// Accessible name of the card action, e.g. "Riwayat glukosa".
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final String? footnote;

  /// Larger value (Insights) instead of the compact one (Today).
  final bool prominentValue;
  final Color tint, ink;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    final body = Padding(
      padding: const EdgeInsets.all(AppSpacing.cardPadding - 2).copyWith(
        left: AppSpacing.cardPadding,
        right: AppSpacing.cardPadding - 2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: ink),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(title, style: AppTypography.title),
                  ),
                  if (badge != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: badge!,
                    ),
                  if (hasValue) ...[
                    const SizedBox(height: 2),
                    Text(
                      value!,
                      style: prominentValue
                          ? AppTypography.metricLarge.copyWith(fontSize: 24)
                          : AppTypography.metric,
                    ),
                    if (valueCaption != null)
                      Text(valueCaption!, style: AppTypography.caption),
                  ] else if (emptyMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        emptyMessage!,
                        style: AppTypography.secondary,
                      ),
                    ),
                  for (final detail in details)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(detail, style: AppTypography.secondary),
                    ),
                  if (footnote != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(footnote!, style: AppTypography.caption),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          if (primaryLabel != null)
            Tooltip(
              message: primaryLabel!,
              child: Semantics(
                button: true,
                label: primaryLabel,
                excludeSemantics: true,
                onTap: onPrimary,
                child: SizedBox(
                  // 48dp touch target around a 40dp visual button.
                  height: AppSpacing.minTouchTarget,
                  width: AppSpacing.minTouchTarget,
                  child: Center(
                    child: Material(
                      color: tint,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onPrimary,
                        child: SizedBox(
                          height: 40,
                          width: 40,
                          child: Icon(Icons.add_rounded, size: 22, color: ink),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          else if (onSecondary != null)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Icon(
                Icons.chevron_right_rounded,
                color: AppColors.decorative,
              ),
            ),
        ],
      ),
    );

    final card = Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: onSecondary == null
          ? body
          : InkWell(
              borderRadius: AppRadius.cardRadius,
              onTap: onSecondary,
              child: body,
            ),
    );
    return card;
  }
}
