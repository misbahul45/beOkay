import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/tab_root_header.dart';
import '../../../core/widgets/charts.dart';
import '../../activity/application/activity_controller.dart';
import '../../activity/data/activity_models.dart';
import '../../glucose/application/glucose_controller.dart';
import '../../glucose/data/glucose_models.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/domain_style.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/metric_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../nutrition/data/nutrition_models.dart';
import '../application/insights_controller.dart';
import '../data/daily_insights.dart';
import 'contextual_card.dart';
import 'weekly_card.dart';

/// "Wawasan" tab: descriptive daily summary with explicit coverage and freshness.
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(dailyInsightsProvider);
    return PageScaffold(
      showBack: false,
      onRefresh: () async {
        ref.invalidate(dailyInsightsProvider);
        ref.invalidate(contextualInsightsProvider);
        await ref.read(dailyInsightsProvider.future).catchError((_) => null);
      },
      children: [
        const TabRootHeader(
          title: 'Wawasan',
          subtitle:
              'Ringkasan dari catatanmu sendiri. Bukan diagnosis dan bukan saran medis.',
        ),
        const SizedBox(height: AppSpacing.md),
        const ContextualCard(),
        const _TrendsEntry(),
        const SizedBox(height: AppSpacing.sm),
        _DayNavigator(shown: insights.value?.date),
        const SizedBox(height: AppSpacing.md),
        insights.when(
          skipLoadingOnReload: false,
          skipLoadingOnRefresh: true,
          loading: () => const SkeletonList(rows: 3),
          error: (error, _) {
            if (error is ApiException && error.code == 'CONSENT_REQUIRED') {
              return InfoCard(
                title: 'Persetujuan diperlukan',
                text:
                    'Ringkasan memakai data kesehatanmu. Tinjau persetujuan untuk membukanya.',
                action: PillButton(
                  label: 'Kelola persetujuan',
                  expand: false,
                  onPressed: () => context.push(Routes.consentManagement),
                ),
              );
            }
            return ErrorState(
              error: error,
              onRetry: () => ref.invalidate(dailyInsightsProvider),
            );
          },
          data: (data) =>
              data == null ? const SizedBox.shrink() : _Summary(data: data),
        ),
      ],
    );
  }
}

/// Pintu ke grafik tren (konsistensi, aktivitas, glukosa) dengan rentang 7–90 hari.
class _TrendsEntry extends StatelessWidget {
  const _TrendsEntry();
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Tren harianmu. Lihat perubahan dari hari ke hari.',
    excludeSemantics: true,
    onTap: () => context.push(Routes.trends),
    child: Material(
      color: AppColors.brand,
      borderRadius: AppRadius.cardRadius,
      child: InkWell(
        borderRadius: AppRadius.cardRadius,
        onTap: () => context.push(Routes.trends),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const Icon(Icons.show_chart_rounded, color: AppColors.onPrimary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tren harianmu',
                      style: AppTypography.bodyStrong.copyWith(
                        color: AppColors.onPrimary,
                      ),
                    ),
                    Text(
                      'Lihat perubahanmu dari hari ke hari',
                      style: AppTypography.secondary.copyWith(
                        color: AppColors.brandTint,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.onPrimary,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DayNavigator extends ConsumerWidget {
  const _DayNavigator({required this.shown});

  final String? shown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = shown == null ? null : DateTime.tryParse(shown!);
    final today = DateTime.now();
    final isToday =
        current != null &&
        DateFormat('yyyy-MM-dd').format(current) ==
            DateFormat('yyyy-MM-dd').format(today);
    void go(DateTime day) => ref
        .read(insightsDateProvider.notifier)
        .set(DateFormat('yyyy-MM-dd').format(day));

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.pillRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Hari sebelumnya',
            constraints: const BoxConstraints(
              minWidth: AppSpacing.minTouchTarget,
              minHeight: AppSpacing.minTouchTarget,
            ),
            onPressed: current == null
                ? null
                : () => go(current.subtract(const Duration(days: 1))),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Semantics(
              button: true,
              label: 'Pilih tanggal',
              excludeSemantics: true,
              onTap: current == null ? null : () => _pick(context, current, go),
              child: InkWell(
                borderRadius: AppRadius.pillRadius,
                onTap: current == null
                    ? null
                    : () => _pick(context, current, go),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  child: Center(
                    child: Text(
                      current == null
                          ? 'Memuat…'
                          : '${isToday ? 'Hari ini · ' : ''}${DateFormat('d MMMM y', 'id_ID').format(current)}',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyStrong,
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Hari berikutnya',
            constraints: const BoxConstraints(
              minWidth: AppSpacing.minTouchTarget,
              minHeight: AppSpacing.minTouchTarget,
            ),
            onPressed: current == null || isToday
                ? null
                : () => go(current.add(const Duration(days: 1))),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  Future<void> _pick(
    BuildContext context,
    DateTime current,
    void Function(DateTime) go,
  ) async {
    final now = DateTime.now();
    final chosen = await showDatePicker(
      context: context,
      initialDate: current.isAfter(now) ? now : current,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (chosen != null) go(chosen);
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.data});

  final DailyInsights data;

  @override
  Widget build(BuildContext context) {
    final glucose = data.glucose;
    final unit = glucose.displayUnit;
    String fmt(num v) => v.toStringAsFixed(unit == 'mmol/L' ? 1 : 0);
    final enoughGlucose =
        glucose.analyticsState == 'READY' && glucose.mean != null;
    final nutrition = data.nutrition;
    final activity = data.activity;
    final calories = nutrition.totals['calories'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data.isEmpty) ...[
          const InfoCard(
            tone: InfoTone.neutral,
            title: 'Belum ada catatan di hari ini',
            text: 'Ringkasan muncul setelah ada catatan.',
          ),
          const SizedBox(height: 10),
        ],
        MetricCard(
          icon: DomainStyle.glucose.icon,
          tint: DomainStyle.glucose.tint,
          ink: DomainStyle.glucose.ink,
          title: 'Glukosa',
          badge: glucose.count == 0
              ? null
              : StatusBadge(
                  label: enoughGlucose
                      ? 'Statistik tersedia'
                      : 'Data belum cukup',
                  tone: enoughGlucose ? InfoTone.info : InfoTone.neutral,
                ),
          prominentValue: true,
          value: glucose.latest?.label,
          valueCaption: glucose.latest == null
              ? null
              : 'Pengukuran terakhir pukul ${glucose.latest!.localTime}',
          emptyMessage: 'Belum ada pengukuran.',
          details: [
            if (glucose.count > 0) '${glucose.count} pengukuran manual dicatat',
            if (enoughGlucose) ...[
              'Rata-rata ${fmt(glucose.mean!)} $unit',
              if (glucose.minimum != null && glucose.maximum != null)
                'Terendah ${fmt(glucose.minimum!)} · tertinggi ${fmt(glucose.maximum!)} $unit',
            ] else if (glucose.count > 0)
              'Statistik ringkasan belum ditampilkan karena data masih sedikit.',
            if (glucose.reviewCount > 0)
              '${glucose.reviewCount} pengukuran perlu ditinjau',
          ],
          footnote: glucose.count == 0
              ? null
              : _footnote(glucose.freshness, glucose.computedAt),
          secondaryLabel: 'Riwayat glukosa',
          onSecondary: () => context.push(Routes.glucose),
        ),
        const SizedBox(height: 10),
        MetricCard(
          icon: DomainStyle.meal.icon,
          tint: DomainStyle.meal.tint,
          ink: DomainStyle.meal.ink,
          title: 'Nutrisi',
          prominentValue: true,
          value: nutrition.mealCount == 0
              ? null
              : '${nutrition.mealCount} catatan makan',
          emptyMessage: 'Belum ada catatan makan.',
          details: [
            if (nutrition.mealCount > 0) ...[
              'Energi: ${calories?.label('kkal') ?? 'Belum tersedia'}',
              for (final key in ['carbohydrates', 'protein', 'fat', 'fiber'])
                if (nutrition.totals[key]?.value != null)
                  '${nutrientLabels[key]}: ${nutrition.totals[key]!.label('g')}',
              if (nutrition.totals.values.any((t) => t.coverage != 'COMPLETE'))
                'Nilai yang belum diketahui tidak dihitung sebagai nol.',
            ],
          ],
          footnote: nutrition.mealCount == 0
              ? null
              : _footnote(data.nutritionFreshness, data.nutritionComputedAt),
          secondaryLabel: 'Riwayat makanan',
          onSecondary: () => context.push(Routes.meals),
        ),
        const SizedBox(height: 10),
        MetricCard(
          icon: DomainStyle.activity.icon,
          tint: DomainStyle.activity.tint,
          ink: DomainStyle.activity.ink,
          title: 'Aktivitas',
          badge: activity.reviewCount > 0
              ? StatusBadge(
                  label: '${activity.reviewCount} perlu ditinjau',
                  tone: InfoTone.warning,
                )
              : null,
          prominentValue: true,
          value: activity.count == 0
              ? null
              : '${activity.durationMinutes ?? 0} menit',
          valueCaption: activity.count == 0
              ? null
              : '${activity.count} sesi dilaporkan sendiri',
          emptyMessage: 'Belum ada sesi aktivitas.',
          details: [
            if (activity.count > 0) ...[
              'Langkah: ${activity.steps.label('langkah')}',
              'Jarak: ${activity.distanceKm.label('km')}',
            ],
          ],
          footnote: activity.count == 0
              ? null
              : _footnote('CURRENT', activity.computedAt),
          secondaryLabel: 'Tinjauan mingguan',
          onSecondary: () => context.push(Routes.activityWeek),
        ),
        const SizedBox(height: AppSpacing.md),
        _Charts(date: data.date),
        const SizedBox(height: AppSpacing.md),
        const WeeklyCard(),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Angka berasal dari catatanmu sendiri. "–" berarti tidak ada catatan, bukan nol. Bukan diagnosis atau saran medis.',
          style: AppTypography.caption,
        ),
      ],
    );
  }

  static String? _footnote(String freshness, String? computedAt) {
    final time = computedAt == null
        ? null
        : DateTime.tryParse(computedAt)?.toLocal();
    final label = freshness == 'CURRENT'
        ? 'terkini'
        : 'mungkin sudah berubah, tarik untuk memuat ulang';
    return 'Dihitung dari catatanmu · $label${time == null ? '' : ' · ${DateFormat('HH:mm').format(time)}'}';
  }
}

/// Charts for the shown day: weekly activity bars and sparse glucose dots.
class _Charts extends ConsumerWidget {
  const _Charts({required this.date});
  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(activityWeekProvider(date)).value;
    final glucose = ref
        .watch(glucosePageProvider((cursor: null, date: date, archived: false)))
        .value;
    final unit = glucose?.displayUnit ?? 'mg/dL';
    final points = [
      for (final r in glucose?.items ?? const <GlucoseRecord>[])
        DotPoint(
          minuteOfDay:
              int.parse(r.localTime.substring(0, 2)) * 60 +
              int.parse(r.localTime.substring(3, 5)),
          value: r.displayValue,
          needsReview: r.qualityStatus == 'needs_review',
        ),
    ];
    final days = week?.days ?? const <ActivityDay>[];
    final slots = [
      for (final d in days)
        BarSlot(
          label: DateFormat('E', 'id_ID').format(DateTime.parse(d.date)),
          value: d.eligibleCount == 0 ? null : d.durationMinutes,
        ),
    ];
    final recorded = slots.where((s) => s.value != null).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text('Grafik', style: AppTypography.heading),
        ),
        const SizedBox(height: AppSpacing.xs + 2),
        ChartCard(
          icon: DomainStyle.activity.icon,
          tint: DomainStyle.activity.tint,
          ink: DomainStyle.activity.ink,
          title: 'Aktivitas 7 hari (menit)',
          empty: slots.isEmpty || recorded == 0
              ? 'Belum ada sesi aktivitas pada minggu ini.'
              : null,
          caption:
              'Batang dimulai dari nol. Hari tanpa catatan tampil sebagai "–".',
          child: BarChart(
            slots: slots,
            unit: 'menit',
            color: AppColors.activityInk,
            tint: AppColors.activityTint,
            semanticLabel:
                'Grafik batang aktivitas 7 hari. $recorded dari ${slots.length} hari memiliki catatan.',
          ),
        ),
        const SizedBox(height: 10),
        ChartCard(
          icon: DomainStyle.glucose.icon,
          tint: DomainStyle.glucose.tint,
          ink: DomainStyle.glucose.ink,
          title: 'Glukosa hari ini ($unit)',
          empty: points.isEmpty ? 'Belum ada pengukuran pada hari ini.' : null,
          caption:
              'Setiap titik satu pengukuran manual; tidak dihubungkan karena nilai di antaranya tidak diketahui. Lingkaran kosong: perlu ditinjau.',
          child: DotPlot(
            points: points,
            unit: unit,
            color: AppColors.glucoseInk,
            semanticLabel:
                'Grafik titik glukosa. ${points.length} pengukuran pada hari ini.',
          ),
        ),
      ],
    );
  }
}
