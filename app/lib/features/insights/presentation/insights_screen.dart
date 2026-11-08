import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/domain_style.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/metric_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../quick_record/presentation/quick_record_sheet.dart';
import '../../nutrition/data/nutrition_models.dart';
import '../application/insights_controller.dart';
import '../data/daily_insights.dart';

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
        await ref.read(dailyInsightsProvider.future).catchError((_) => null);
      },
      children: [
        Semantics(header: true, child: Text('Wawasan', style: AppTypography.headline)),
        const SizedBox(height: AppSpacing.xs),
        Text('Ringkasan dari catatanmu sendiri. Bukan diagnosis dan bukan saran medis.', style: AppTypography.secondary),
        const SizedBox(height: AppSpacing.md),
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
                text: 'Ringkasan memakai data kesehatanmu. Tinjau persetujuan untuk membukanya.',
                action: PillButton(label: 'Kelola persetujuan', expand: false, onPressed: () => context.push(Routes.consentManagement)),
              );
            }
            return ErrorState(error: error, onRetry: () => ref.invalidate(dailyInsightsProvider));
          },
          data: (data) => data == null ? const SizedBox.shrink() : _Summary(data: data),
        ),
      ],
    );
  }
}

class _DayNavigator extends ConsumerWidget {
  const _DayNavigator({required this.shown});

  final String? shown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = shown == null ? null : DateTime.tryParse(shown!);
    final today = DateTime.now();
    final isToday = current != null && DateFormat('yyyy-MM-dd').format(current) == DateFormat('yyyy-MM-dd').format(today);
    void go(DateTime day) => ref.read(insightsDateProvider.notifier).set(DateFormat('yyyy-MM-dd').format(day));

    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.pillRadius, border: Border.all(color: AppColors.border)),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Hari sebelumnya',
            constraints: const BoxConstraints(minWidth: AppSpacing.minTouchTarget, minHeight: AppSpacing.minTouchTarget),
            onPressed: current == null ? null : () => go(current.subtract(const Duration(days: 1))),
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
                onTap: current == null ? null : () => _pick(context, current, go),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
                  child: Center(
                    child: Text(
                      current == null ? 'Memuat…' : '${isToday ? 'Hari ini · ' : ''}${DateFormat('d MMMM y', 'id_ID').format(current)}',
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
            constraints: const BoxConstraints(minWidth: AppSpacing.minTouchTarget, minHeight: AppSpacing.minTouchTarget),
            onPressed: current == null || isToday ? null : () => go(current.add(const Duration(days: 1))),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  Future<void> _pick(BuildContext context, DateTime current, void Function(DateTime) go) async {
    final now = DateTime.now();
    final chosen = await showDatePicker(context: context, initialDate: current.isAfter(now) ? now : current, firstDate: DateTime(2000), lastDate: now);
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
    final enoughGlucose = glucose.analyticsState == 'READY' && glucose.mean != null;
    final nutrition = data.nutrition;
    final activity = data.activity;
    final calories = nutrition.totals['calories'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data.isEmpty) ...[
          EmptyState(
            icon: Icons.insights_rounded,
            title: 'Belum ada catatan di hari ini',
            message: 'Ringkasan muncul setelah ada catatan. Tidak ada angka yang dikarang untuk mengisi kekosongan.',
            actionLabel: 'Catat sekarang',
            onAction: () => showQuickRecord(context),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        MetricCard(
          icon: DomainStyle.glucose.icon,
          title: 'Glukosa',
          badge: glucose.count == 0
              ? null
              : StatusBadge(label: enoughGlucose ? 'Statistik tersedia' : 'Data belum cukup', tone: enoughGlucose ? InfoTone.info : InfoTone.neutral),
          value: glucose.latest?.label,
          valueCaption: glucose.latest == null ? null : 'Pengukuran terakhir pukul ${glucose.latest!.localTime}',
          emptyMessage: 'Belum ada pengukuran pada hari ini.',
          details: [
            if (glucose.count > 0) '${glucose.count} pengukuran manual dicatat',
            if (enoughGlucose) ...[
              'Rata-rata ${fmt(glucose.mean!)} $unit',
              if (glucose.minimum != null && glucose.maximum != null) 'Terendah ${fmt(glucose.minimum!)} · tertinggi ${fmt(glucose.maximum!)} $unit',
            ] else if (glucose.count > 0)
              'Statistik ringkasan belum ditampilkan karena data masih sedikit.',
            if (glucose.reviewCount > 0) '${glucose.reviewCount} pengukuran perlu ditinjau',
          ],
          footnote: _footnote(glucose.freshness, glucose.computedAt),
          secondaryLabel: 'Riwayat glukosa',
          onSecondary: () => context.push(Routes.glucose),
        ),
        const SizedBox(height: AppSpacing.sm),
        MetricCard(
          icon: DomainStyle.meal.icon,
          title: 'Nutrisi',
          value: nutrition.mealCount == 0 ? null : '${nutrition.mealCount} catatan makan',
          emptyMessage: 'Belum ada catatan makanan pada hari ini.',
          details: [
            if (nutrition.mealCount > 0) ...[
              'Energi: ${calories?.label('kkal') ?? 'Belum tersedia'}',
              for (final key in ['carbohydrates', 'protein', 'fat', 'fiber'])
                if (nutrition.totals[key]?.value != null) '${nutrientLabels[key]}: ${nutrition.totals[key]!.label('g')}',
              if (nutrition.totals.values.any((t) => t.coverage != 'COMPLETE')) 'Nilai yang belum diketahui tidak dihitung sebagai nol.',
            ],
          ],
          footnote: _footnote(data.nutritionFreshness, data.nutritionComputedAt),
          secondaryLabel: 'Riwayat makanan',
          onSecondary: () => context.push(Routes.meals),
        ),
        const SizedBox(height: AppSpacing.sm),
        MetricCard(
          icon: DomainStyle.activity.icon,
          title: 'Aktivitas',
          badge: activity.reviewCount > 0 ? StatusBadge(label: '${activity.reviewCount} perlu ditinjau', tone: InfoTone.warning) : null,
          value: activity.count == 0 ? null : '${activity.durationMinutes ?? 0} menit',
          valueCaption: activity.count == 0 ? null : '${activity.count} sesi dilaporkan sendiri',
          emptyMessage: 'Belum ada sesi aktivitas pada hari ini.',
          details: [
            if (activity.count > 0) ...['Langkah: ${activity.steps.label('langkah')}', 'Jarak: ${activity.distanceKm.label('km')}'],
          ],
          footnote: _footnote('CURRENT', activity.computedAt),
          secondaryLabel: 'Tinjauan mingguan',
          onSecondary: () => context.push(Routes.activityWeek),
        ),
        const SizedBox(height: AppSpacing.md),
        const InfoCard(
          tone: InfoTone.neutral,
          title: 'Cara membaca ringkasan',
          text:
              'Semua angka berasal dari catatan yang kamu input sendiri. "Belum diketahui" berarti tidak ada datanya, bukan nol. Ringkasan tidak memberi diagnosis, target klinis, atau saran pengobatan.',
        ),
        const SizedBox(height: AppSpacing.sm),
        const InfoCard(
          tone: InfoTone.neutral,
          icon: Icons.schedule_rounded,
          title: 'Sedang disiapkan',
          text: 'Ringkasan obat, tujuan personal, dan tinjauan mingguan lintas domain.',
        ),
      ],
    );
  }

  static String? _footnote(String freshness, String? computedAt) {
    final time = computedAt == null ? null : DateTime.tryParse(computedAt)?.toLocal();
    final label = freshness == 'CURRENT' ? 'terkini' : 'mungkin sudah berubah, tarik untuk memuat ulang';
    return 'Dihitung dari catatanmu · $label${time == null ? '' : ' · ${DateFormat('HH:mm').format(time)}'}';
  }
}
