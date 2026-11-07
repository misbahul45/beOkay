import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/info_card.dart';
import '../data/consent_models.dart';

class ConsentPurposeCard extends StatelessWidget {
  const ConsentPurposeCard({super.key, required this.purpose, required this.footer, this.badge});

  final PolicyPurpose purpose;
  final Widget footer;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.cardRadius, boxShadow: AppShadows.soft),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              StatusBadge(label: purpose.required ? 'Wajib' : 'Opsional', tone: purpose.required ? InfoTone.info : InfoTone.neutral),
              ?badge,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(purpose.title, style: AppTypography.title),
          const SizedBox(height: AppSpacing.xxs),
          Text(purpose.description, style: AppTypography.secondary),
          const SizedBox(height: AppSpacing.sm),
          Text('DATA YANG TERLIBAT', style: AppTypography.overline),
          const SizedBox(height: 4),
          for (final category in purpose.dataCategories)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.only(top: 7, right: 8), child: Icon(Icons.circle, size: 5, color: AppColors.textSecondary)),
                  Expanded(child: Text(category, style: AppTypography.secondary)),
                ],
              ),
            ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: Material(
              color: Colors.transparent,
              child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: AppSpacing.xs),
              title: Text('Jika persetujuan ditarik', style: AppTypography.secondaryStrong),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(purpose.withdrawalEffect, style: AppTypography.secondary)],
              ),
            ),
          ),
          footer,
        ],
      ),
    );
  }
}
