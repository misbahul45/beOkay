import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/pill_button.dart';
import '../application/insights_controller.dart';
import '../data/statistics.dart';
import 'insight_presentation.dart';
import 'insight_widgets.dart';

const primaryInsightCount = 2;

void runInsightAction(BuildContext context, WidgetRef ref, InsightAction a) {
  switch (a) {
    case InsightAction.openTrends:
      ref.read(insightsSectionProvider.notifier).set(InsightsSection.trends);
    case InsightAction.logMeal:
      context.push(Routes.addMeal);
    case InsightAction.openGlucose:
      context.push(Routes.glucose);
    case InsightAction.openMedication:
      context.push(Routes.medications);
    case InsightAction.askCoach:
      context.go(Routes.coach);
    case InsightAction.createGoal:
      context.push(Routes.addGoal);
  }
}

class ConsentNeeded extends StatelessWidget {
  const ConsentNeeded({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => InfoCard(
    title: 'Persetujuan diperlukan',
    text: text,
    action: PillButton(
      label: 'Kelola persetujuan',
      expand: false,
      onPressed: () => context.push(Routes.consentManagement),
    ),
  );
}

class SummaryTab extends ConsumerWidget {
  const SummaryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(trendRangeProvider);
    final async = ref.watch(statisticsProvider(days));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PeriodSelector(),
        const SizedBox(height: AppSpacing.sm),
        async.when(
          skipLoadingOnReload: true,
          skipLoadingOnRefresh: true,
          loading: () => const SkeletonList(rows: 3),
          error: (error, _) =>
              error is ApiException && error.code == 'CONSENT_REQUIRED'
              ? const ConsentNeeded(
                  text:
                      'Ringkasan memakai data kesehatanmu. Tinjau persetujuan untuk membukanya.',
                )
              : ErrorState(
                  error: error,
                  onRetry: () => ref.invalidate(statisticsProvider(days)),
                ),
          data: (s) => s == null
              ? const SizedBox.shrink()
              : AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: async.isLoading ? 0.45 : 1,
                  child: IgnorePointer(
                    ignoring: async.isLoading,
                    child: s.ready
                        ? _SummaryBody(stats: s)
                        : _EmptySummary(days: s.days),
                  ),
                ),
        ),
      ],
    );
  }
}

class _EmptySummary extends StatelessWidget {
  const _EmptySummary({required this.days});
  final int days;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg - 2),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Belum ada catatan di $days hari terakhir',
          style: AppTypography.title,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Catat makanan, glukosa, atau aktivitas untuk mulai melihat polamu.',
          style: AppTypography.secondary,
        ),
        const SizedBox(height: AppSpacing.sm),
        PillButton(
          label: 'Mulai mencatat',
          expand: false,
          onPressed: () => context.go(Routes.log),
        ),
      ],
    ),
  );
}

class _SummaryBody extends ConsumerStatefulWidget {
  const _SummaryBody({required this.stats});
  final Statistics stats;

  @override
  ConsumerState<_SummaryBody> createState() => _SummaryBodyState();
}

class _SummaryBodyState extends ConsumerState<_SummaryBody> {
  bool showAll = false;

  void _act(InsightAction a) => runInsightAction(context, ref, a);

  (String, VoidCallback)? _metricAction(MetricPresentation m) =>
      switch (m.domain) {
        'activity' => (
          'Lihat tren',
          () => ref
              .read(insightsSectionProvider.notifier)
              .set(InsightsSection.trends),
        ),
        'glucose' => ('Buka glukosa', () => context.push(Routes.glucose)),
        'nutrition' => ('Riwayat makanan', () => context.push(Routes.meals)),
        'medication' => ('Buka obat', () => context.push(Routes.medications)),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final s = widget.stats;
    final insights = prioritizeInsights(s);
    final shown = showAll
        ? insights
        : insights.take(primaryInsightCount).toList();
    final logged = s.byId('logging.recorded_days');
    final metrics = overviewMetrics(s);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (logged != null && logged.value != null)
          DataQualityHint(have: logged.value!.round(), total: s.days),
        const SizedBox(height: AppSpacing.sm),
        if (insights.isEmpty)
          Text(
            'Belum ada pola yang cukup kuat untuk disebut.',
            style: AppTypography.secondary,
          )
        else ...[
          for (final i in shown) ...[
            InsightCard(
              insight: i,
              onOpen: () => showInsightDetail(
                context,
                stats: s,
                insight: i,
                onAction: _act,
              ),
              onAction: _act,
            ),
            const SizedBox(height: AppSpacing.sm - 2),
          ],
          if (insights.length > primaryInsightCount)
            TextButton(
              onPressed: () => setState(() => showAll = !showAll),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: Colors.transparent,
                minimumSize: const Size(0, AppSpacing.minTouchTarget),
              ),
              child: Text(
                showAll
                    ? 'Tampilkan lebih sedikit'
                    : 'Lihat semua wawasan (${insights.length})',
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.md),
        Semantics(
          header: true,
          child: Text('Ikhtisar', style: AppTypography.heading),
        ),
        const SizedBox(height: AppSpacing.sm),
        MetricGrid(
          metrics: metrics,
          onOpen: (m) {
            final action = _metricAction(m);
            showMetricDetail(
              context,
              stats: s,
              metric: m,
              actionLabel: action?.$1,
              onAction: action?.$2,
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton.icon(
          onPressed: () => showAboutWawasan(context, updatedAt: s.computedAt),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: Colors.transparent,
            foregroundColor: AppColors.textSecondary,
            minimumSize: const Size(0, AppSpacing.minTouchTarget),
          ),
          icon: const Icon(Icons.info_outline_rounded, size: 18),
          label: const Text('Tentang data ini'),
        ),
      ],
    );
  }
}
