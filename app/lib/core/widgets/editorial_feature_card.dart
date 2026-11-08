import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

class EditorialFeatureCard extends StatelessWidget {
  const EditorialFeatureCard({
    super.key,
    required this.title,
    required this.description,
  });
  final String title, description;
  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.primary,
    borderRadius: AppRadius.cardRadius,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.heading.copyWith(color: AppColors.onPrimary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            description,
            style: AppTypography.body.copyWith(color: AppColors.onPrimary),
          ),
        ],
      ),
    ),
  );
}
