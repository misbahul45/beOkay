import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'beokay_avatar.dart';

class AdaptiveHeroCard extends StatelessWidget {
  const AdaptiveHeroCard({
    super.key,
    required this.title,
    this.kicker,
    this.detail,
    this.sparkState = SparkState.idle,
    this.background,
    this.action,
  });

  final String title;
  final String? kicker;
  final String? detail;
  final SparkState sparkState;
  final Color? background;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm + 2,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: background ?? AppColors.brandTint,
        borderRadius: BorderRadius.circular(AppRadius.hero),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BeOkayAvatar(size: 72, state: sparkState),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (kicker != null)
                      Text(
                        kicker!.toUpperCase(),
                        style: AppTypography.overline.copyWith(
                          color: AppColors.infoForeground,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Semantics(
                      header: true,
                      liveRegion: true,
                      child: Text(
                        title,
                        style: AppTypography.headline.copyWith(
                          fontSize: 20,
                          height: 1.3,
                        ),
                      ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: 2),
                      Text(detail!, style: AppTypography.secondary),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.sm),
            action!,
          ],
        ],
      ),
    );
  }
}
