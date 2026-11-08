import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'pill_button.dart';

/// Explains why a list is empty and offers the single most likely next action.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.actionLabel, this.onAction});

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.cardRadius),
      child: Column(
        children: [
          ExcludeSemantics(
            child: Container(
              height: 56,
              width: 56,
              decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.primary, size: 28),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Semantics(header: true, child: Text(title, textAlign: TextAlign.center, style: AppTypography.title)),
          const SizedBox(height: AppSpacing.xs),
          Text(message, textAlign: TextAlign.center, style: AppTypography.secondary),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.lg),
            PillButton(label: actionLabel!, onPressed: onAction, expand: false),
          ],
        ],
      ),
    );
  }
}
