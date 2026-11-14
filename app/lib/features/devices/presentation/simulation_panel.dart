import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/soft_card.dart';
import '../application/devices_controller.dart';
import '../data/simulated_source.dart';

class SimulationBanner extends ConsumerWidget {
  const SimulationBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = simulationAvailable
        ? ref.watch(simulationProfileProvider)
        : null;
    if (profile == null) return const SizedBox.shrink();
    return Semantics(
      container: true,
      label: 'Data simulasi. Bukan pengukuran nyata.',
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.warningBackground,
          borderRadius: AppRadius.cardRadius,
        ),
        child: Row(
          children: [
            Icon(
              Icons.science_outlined,
              size: 18,
              color: AppColors.warningForeground,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                'DATA SIMULASI · ${profile.label}. Bukan pengukuran nyata dan tidak dipakai untuk saran.',
                style: AppTypography.caption.copyWith(
                  color: AppColors.warningForeground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SimulationPanel extends ConsumerWidget {
  const SimulationPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!simulationAvailable) return const SizedBox.shrink();
    final active = ref.watch(simulationProfileProvider);
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MODE SIMULASI (PENGEMBANGAN)', style: AppTypography.overline),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Menjalankan alur impor yang sama dengan data simulasi. Server produksi menolak data ini.',
            style: AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final p in SimulationProfile.values)
                ChoiceChip(
                  label: Text(p.label),
                  selected: active == p,
                  onSelected: (on) {
                    ref
                        .read(simulationProfileProvider.notifier)
                        .use(on ? p : null);
                    ref.read(deviceConnectionProvider.notifier).refresh();
                  },
                ),
            ],
          ),
          if (active != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  ref.read(simulationProfileProvider.notifier).use(null);
                  ref.read(deviceConnectionProvider.notifier).refresh();
                },
                child: const Text('Matikan simulasi'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
