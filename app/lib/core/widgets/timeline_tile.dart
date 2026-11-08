import 'package:flutter/material.dart';

import '../../features/timeline/data/timeline_models.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'domain_style.dart';

/// One timeline event. The whole row is one 64dp+ touch target that opens the original record.
class TimelineTile extends StatelessWidget {
  const TimelineTile({super.key, required this.item, required this.onTap});

  final TimelineItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = DomainStyle.of(item.domain);
    return Semantics(
      button: true,
      label: '${style.label}: ${item.title}. ${item.subtitle}',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        child: InkWell(
          borderRadius: AppRadius.cardRadius,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Container(
                    height: 44,
                    width: 44,
                    decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                    child: Icon(style.icon, size: 22, color: AppColors.primary),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title, style: AppTypography.bodyStrong),
                        const SizedBox(height: 2),
                        Text(item.subtitle, style: AppTypography.secondary),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.decorative),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
