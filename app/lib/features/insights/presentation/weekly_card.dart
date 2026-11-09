import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/domain_style.dart';
import '../application/insights_controller.dart';

/// Satu kartu: berapa hari dalam minggu ini yang punya catatan, per domain. Tidak menilai apa pun.
class WeeklyCard extends ConsumerWidget {
  const WeeklyCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(weeklyInsightsProvider).value;
    if (w == null) return const SizedBox.shrink();
    return Semantics(
      container: true,
      label: 'Ringkasan minggu ${w.weekStart} sampai ${w.weekEnd}. ${w.recordedDays} dari ${w.totalDays} hari ada catatan.',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.cardRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Minggu ini', style: AppTypography.bodyStrong),
            const SizedBox(height: 2),
            Text(
              w.hasData ? '${w.recordedDays} dari ${w.totalDays} hari ada catatan' : 'Belum ada catatan minggu ini',
              style: AppTypography.secondary,
            ),
            if (w.hasData) ...[
              const SizedBox(height: AppSpacing.sm),
              _Row(DomainStyle.meal, 'Makanan', '${w.mealDays} hari'),
              _Row(DomainStyle.glucose, 'Glukosa', '${w.glucoseDays} hari'),
              _Row(DomainStyle.activity, 'Aktivitas', w.activityMinutes == null ? '–' : '${w.activityMinutes} menit'),
              if (w.medScheduled > 0)
                _Row(
                  DomainStyle.medication,
                  'Obat',
                  '${w.medTaken} dikonfirmasi${w.medUnconfirmed > 0 ? ', ${w.medUnconfirmed} belum' : ''}',
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.style, this.label, this.value);
  final DomainStyle style;
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Container(
          height: 28,
          width: 28,
          decoration: BoxDecoration(color: style.tint, shape: BoxShape.circle),
          child: Icon(style.icon, size: 16, color: style.ink),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(label, style: AppTypography.body)),
        Text(value, style: AppTypography.bodyStrong),
      ],
    ),
  );
}
