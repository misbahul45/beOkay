import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/info_card.dart';
import '../application/insights_controller.dart';

/// "Catatan untukmu": maksimal tiga pengamatan tentang kebiasaan mencatat. Tidak menilai angka kesehatan.
class ContextualCard extends ConsumerWidget {
  const ContextualCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(contextualInsightsProvider).value;
    if (data == null || data.items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text('Catatan untukmu', style: AppTypography.title),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final item in data.items) ...[
          InfoCard(
            tone: InfoTone.neutral,
            title: item.title,
            text: item.body,
            icon: Icons.lightbulb_outline,
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        const SizedBox(height: AppSpacing.xs),
      ],
    );
  }
}
