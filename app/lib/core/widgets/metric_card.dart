import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'info_card.dart';
import 'pill_button.dart';

/// Domain summary card used on Today and Insights.
///
/// Hierarchy: icon + title (+ status) → value → caption → actions.
/// [value] is shown in the large style only when real data exists; an empty
/// domain passes [emptyMessage] instead so "no data" never looks like a number.
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
  });

  final IconData icon;
  final String title;
  final String? value;
  final String? valueCaption;
  final String? emptyMessage;
  final List<String> details;
  final StatusBadge? badge;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.cardRadius, boxShadow: AppShadows.soft),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  height: 40,
                  width: 40,
                  decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                  child: Icon(icon, size: 22, color: AppColors.primary),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Semantics(header: true, child: Text(title, style: AppTypography.title))),
            ],
          ),
          // Own line: a badge beside the title squeezed both into per-letter wrapping at large text sizes.
          if (badge != null) Padding(padding: const EdgeInsets.only(top: AppSpacing.xs), child: badge!),
          const SizedBox(height: AppSpacing.sm),
          if (hasValue) ...[
            Text(value!, style: AppTypography.heading),
            if (valueCaption != null) Text(valueCaption!, style: AppTypography.secondary),
          ] else if (emptyMessage != null)
            Text(emptyMessage!, style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
          for (final detail in details) Padding(padding: const EdgeInsets.only(top: 2), child: Text(detail, style: AppTypography.secondary)),
          if (footnote != null) Padding(padding: const EdgeInsets.only(top: AppSpacing.xs), child: Text(footnote!, style: AppTypography.caption)),
          if (primaryLabel != null || secondaryLabel != null) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (primaryLabel != null) PillButton(label: primaryLabel!, kind: PillButtonKind.secondary, expand: false, icon: Icons.add_rounded, onPressed: onPrimary),
                if (secondaryLabel != null)
                  Semantics(
                    button: true,
                    label: secondaryLabel,
                    excludeSemantics: true,
                    onTap: onSecondary,
                    child: TextButton.icon(
                      onPressed: onSecondary,
                      style: TextButton.styleFrom(minimumSize: const Size(AppSpacing.minTouchTarget, AppSpacing.minTouchTarget), foregroundColor: AppColors.textPrimary),
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.chevron_right_rounded, size: 20),
                      label: Text(secondaryLabel!, style: AppTypography.secondaryStrong),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
