import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../application/community_controller.dart';
import 'community_widgets.dart';

class CommunityHighlightCard extends ConsumerWidget {
  const CommunityHighlightCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = ref.watch(homeHighlightProvider).value;
    if (h == null) return const SizedBox.shrink();
    final challenge = h.type == 'CHALLENGE';
    void open() => context.push(
      challenge && h.challengeId != null
          ? '/challenge/${h.challengeId}'
          : Routes.community,
    );
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Semantics(
        button: true,
        label:
            '${challenge ? 'Tantanganmu' : 'Pencapaian baru'}. ${h.title}. ${h.detail}',
        excludeSemantics: true,
        onTap: open,
        child: Material(
          color: AppColors.surface,
          borderRadius: AppRadius.cardRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: open,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        height: 32,
                        width: 32,
                        decoration: BoxDecoration(
                          color: AppColors.goalTint,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          challenge
                              ? Icons.flag_outlined
                              : Icons.emoji_events_outlined,
                          size: 16,
                          color: AppColors.goalInk,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          challenge ? 'Tantanganmu' : 'Pencapaian baru',
                          style: AppTypography.bodyStrong,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${h.title} · ${h.detail}',
                    style: AppTypography.secondary,
                  ),
                  if (h.ratio != null) ...[
                    const SizedBox(height: 6),
                    ProgressBar(ratio: h.ratio!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
