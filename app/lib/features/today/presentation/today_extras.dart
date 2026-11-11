import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/beokay_spark.dart';
import '../../../core/widgets/domain_style.dart';
import '../../goals/application/goals_controller.dart';
import '../../insights/application/insights_controller.dart';
import '../../insights/data/statistics.dart';
import '../../insights/presentation/statistics_section.dart';
import '../../medication/application/medication_controller.dart';
import '../../nutrition/data/nutrition_models.dart';

List<(String, String, Color)> get _snapshotNutrients => [
  ('carbohydrates', 'Karbohidrat', AppColors.mealSolid),
  ('protein', 'Protein', AppColors.glucoseSolid),
  ('fat', 'Lemak', AppColors.goalSolid),
  ('fiber', 'Serat', AppColors.medicationSolid),
];

BoxDecoration get _card => BoxDecoration(
  color: AppColors.surface,
  borderRadius: AppRadius.cardRadius,
  border: Border.all(color: AppColors.border),
);

class NutritionSnapshotCard extends StatelessWidget {
  const NutritionSnapshotCard({super.key, required this.nutrition});
  final NutritionDay nutrition;

  @override
  Widget build(BuildContext context) {
    final energy = nutrition.totals['calories'];
    final grams = {
      for (final (k, _, _) in _snapshotNutrients)
        k: nutrition.totals[k]?.value?.toDouble(),
    };
    final maxG = grams.values.whereType<double>().fold<double>(0, math.max);
    final notes = <String>[
      for (final (k, label, _) in _snapshotNutrients)
        if (nutrition.totals[k] case final t?
            when t.coverage == 'PARTIAL' && t.value != null)
          '$label hanya dari ${t.knownItems} dari ${t.totalItems} item; sisanya tidak diketahui.',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md - 2),
      decoration: _card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Gizi hari ini', style: AppTypography.title),
                ),
              ),
              Text(
                '${nutrition.mealCount} catatan makan',
                style: AppTypography.caption,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 6,
            children: [
              Text(
                energy?.value == null
                    ? 'Energi belum diketahui'
                    : formatNumber(energy!.value!.toDouble().roundToDouble()),
                style: energy?.value == null
                    ? AppTypography.secondaryStrong
                    : AppTypography.metricLarge,
              ),
              if (energy?.value != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    energy!.coverage == 'PARTIAL'
                        ? 'kkal tercatat · sebagian'
                        : 'kkal tercatat',
                    style: AppTypography.secondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final (k, label, color) in _snapshotNutrients)
            _MacroBar(
              label: label,
              total: nutrition.totals[k],
              fraction: grams[k] == null || maxG == 0 ? 0 : grams[k]! / maxG,
              color: color,
            ),
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(n, style: AppTypography.caption),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Tanpa target: batang membandingkan zat gizi satu sama lain, bukan dengan batas.',
            style: AppTypography.caption,
          ),
        ],
      ),
    );
  }
}

class _MacroBar extends StatelessWidget {
  const _MacroBar({
    required this.label,
    required this.total,
    required this.fraction,
    required this.color,
  });

  final String label;
  final NutrientTotal? total;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final v = total?.value?.toDouble();
    final text = v == null
        ? 'tidak diketahui'
        : '${formatNumber(v)} g${total!.coverage == 'PARTIAL' ? ' · sebagian' : ''}';
    return Semantics(
      label: '$label: $text',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(label, style: AppTypography.secondaryStrong),
                ),
                Text(
                  text,
                  style: v == null
                      ? AppTypography.caption
                      : AppTypography.secondaryStrong,
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                color: color,
                backgroundColor: AppColors.surfaceMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

typedef TodayAction = ({
  IconData icon,
  Color ink,
  String title,
  String detail,
  String route,
});

List<TodayAction> buildTodayActions({
  required DateTime now,
  required int? mealCount,
  required List<({String name, String localTime, DateTime at, String status})>
  medication,
  required List<({String title, bool manual, num? ratio})> goals,
}) {
  final out = <TodayAction>[];
  final due = medication
      .where((m) => m.status == 'unknown' && !m.at.isAfter(now))
      .toList();
  if (due.isNotEmpty) {
    out.add((
      icon: DomainStyle.medication.icon,
      ink: DomainStyle.medication.ink,
      title: due.length == 1
          ? 'Konfirmasi ${due.first.name}'
          : 'Konfirmasi ${due.length} jadwal obat',
      detail: due.length == 1
          ? 'Jadwal ${due.first.localTime} belum dikonfirmasi'
          : 'Sudah lewat dan belum dikonfirmasi',
      route: Routes.medications,
    ));
  }
  if (mealCount == 0 && now.hour >= 11) {
    out.add((
      icon: DomainStyle.meal.icon,
      ink: DomainStyle.meal.ink,
      title: 'Catat makanan',
      detail: 'Belum ada catatan makan hari ini',
      route: Routes.addMeal,
    ));
  }
  for (final g in goals.where((g) => g.manual && (g.ratio ?? 0) < 1).take(1)) {
    out.add((
      icon: DomainStyle.goal.icon,
      ink: DomainStyle.goal.ink,
      title: 'Check-in: ${g.title}',
      detail: 'Tujuan pilihanmu',
      route: Routes.goals,
    ));
  }
  return out.take(3).toList();
}

class TodayActions extends ConsumerWidget {
  const TodayActions({super.key, required this.mealCount});
  final int? mealCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final med = ref.watch(medicationTodayProvider).value;
    final goals = ref.watch(goalsListProvider).value ?? const [];
    final actions = buildTodayActions(
      now: DateTime.now(),
      mealCount: mealCount,
      medication: [
        for (final o in med?.items ?? const [])
          (
            name: o.name,
            localTime: o.localTime,
            at: DateTime.parse(o.scheduledAt),
            status: o.status,
          ),
      ],
      goals: [
        for (final g in goals.where((g) => g.status == 'active'))
          (title: g.title, manual: g.manual, ratio: g.progress?.ratio),
      ],
    );
    if (actions.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md - 2,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      decoration: _card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text('Langkah berikutnya', style: AppTypography.title),
          ),
          for (final a in actions)
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () => context.push(a.route),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppSpacing.minTouchTarget + 8,
                ),
                child: Row(
                  children: [
                    Icon(a.icon, color: a.ink, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(a.title, style: AppTypography.bodyStrong),
                          Text(a.detail, style: AppTypography.caption),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.decorative,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CompanionInsightCard extends ConsumerWidget {
  const CompanionInsightCard({super.key});

  static const days = 14;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Statistics? stats = ref.watch(statisticsProvider(days)).value;
    final card = stats?.insights
        .where((c) => c.domain != 'medication')
        .firstOrNull;
    if (card == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md - 2),
      decoration: BoxDecoration(
        color: AppColors.lavender,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BeOkaySpark(
                size: 40,
                state: card.domain == 'glucose'
                    ? SparkState.neutral
                    : SparkState.encouraging,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Sedikit wawasan hari ini',
                    style: AppTypography.title,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(card.title, style: AppTypography.body),
          const SizedBox(height: AppSpacing.xs),
          DataCoverageIndicator(
            have: card.daysWithData,
            total: card.totalDays,
            label:
                'Dari ${card.daysWithData} dari ${card.totalDays} hari yang tercatat',
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  minimumSize: const Size(0, 44),
                  shape: const StadiumBorder(),
                ),
                onPressed: () {
                  ref.read(trendRangeProvider.notifier).set(days);
                  context.go(Routes.insights);
                },
                child: const Text('Lihat pola'),
              ),
              TextButton(
                style: TextButton.styleFrom(backgroundColor: AppColors.surface),
                onPressed: () => context.go(Routes.coach),
                child: const Text('Tanya beOkay'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
