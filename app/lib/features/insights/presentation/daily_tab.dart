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
import '../../../core/widgets/charts.dart';
import '../../../core/widgets/domain_style.dart';
import '../../../core/widgets/pill_button.dart';
import '../../glucose/application/glucose_controller.dart';
import '../../glucose/data/glucose_models.dart';
import '../../medication/data/medication_repository.dart';
import '../application/insights_controller.dart';
import '../data/daily_insights.dart';
import 'contextual_card.dart';
import 'insight_presentation.dart';
import 'summary_tab.dart';

final _iso = DateFormat('yyyy-MM-dd');

class DailyTab extends ConsumerWidget {
  const DailyTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(dailyInsightsProvider);
    final medication = ref.watch(dailyMedicationProvider);
    final shown = insights.value?.date;
    final isToday = shown != null && shown == _iso.format(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DayNavigator(shown: shown),
        const SizedBox(height: AppSpacing.sm),
        insights.when(
          skipLoadingOnReload: false,
          skipLoadingOnRefresh: true,
          loading: () => const SkeletonList(rows: 3),
          error: (error, _) =>
              error is ApiException && error.code == 'CONSENT_REQUIRED'
              ? const ConsentNeeded(
                  text:
                      'Ringkasan harian memakai data kesehatanmu. Tinjau persetujuan untuk membukanya.',
                )
              : ErrorState(
                  error: error,
                  onRetry: () => ref.invalidate(dailyInsightsProvider),
                ),
          data: (data) {
            if (data == null) return const SizedBox.shrink();
            final med = medication.value;
            final noMedication = med == null || med.scheduled == 0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isToday) const ContextualCard(),
                if (data.isEmpty && noMedication) ...[
                  const _EmptyDay(),
                  const SizedBox(height: AppSpacing.sm),
                ],
                DaySummaryCard(data: data, medication: medication),
                const SizedBox(height: AppSpacing.sm),
                _GlucoseDayChart(date: data.date, isToday: isToday),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay();

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
        Text('Belum ada catatan di hari ini', style: AppTypography.title),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Catat makanan, glukosa, atau aktivitas untuk melihat ringkasannya.',
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

class DayNavigator extends ConsumerWidget {
  const DayNavigator({super.key, required this.shown});

  final String? shown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = shown == null ? null : DateTime.tryParse(shown!);
    final today = DateTime.now();
    final isToday =
        current != null && _iso.format(current) == _iso.format(today);
    void go(DateTime day) =>
        ref.read(insightsDateProvider.notifier).set(_iso.format(day));

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
                          : '${isToday ? 'Hari ini · ' : ''}${DateFormat(isToday ? 'd MMMM' : 'EEEE, d MMMM y', 'id_ID').format(current)}',
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

typedef DayRow = ({
  DomainStyle style,
  String label,
  String? value,
  String caption,
  String route,
  bool push,
});

List<DayRow> dayRows(DailyInsights d, AsyncValue<MedicationToday?> medication) {
  final g = d.glucose;
  final n = d.nutrition;
  final a = d.activity;
  final energy = n.totals['calories'];
  final review = g.reviewCount > 0 ? ' · ${g.reviewCount} perlu ditinjau' : '';
  final med = medication.value;
  return [
    (
      style: DomainStyle.glucose,
      label: 'Glukosa',
      value: g.latest?.label,
      caption: g.count == 0
          ? 'Belum ada pengukuran'
          : 'Terakhir ${g.latest?.localTime.replaceAll(':', '.') ?? '–'} · ${g.count} pengukuran$review',
      route: Routes.glucose,
      push: true,
    ),
    (
      style: DomainStyle.meal,
      label: 'Nutrisi',
      value: n.mealCount == 0
          ? null
          : energy?.value == null
          ? '${n.mealCount} catatan makan'
          : '${formatValue(energy!.value!, whole: true)} kkal',
      caption: n.mealCount == 0
          ? 'Belum ada catatan makan'
          : energy?.value == null
          ? 'Energi belum diketahui'
          : '${n.mealCount} catatan makan${energy!.coverage == 'COMPLETE' ? '' : ' · sebagian item'}',
      route: Routes.meals,
      push: true,
    ),
    (
      style: DomainStyle.activity,
      label: 'Aktivitas',
      value: a.count == 0
          ? null
          : a.durationMinutes == null
          ? '${a.count} sesi'
          : '${a.durationMinutes} menit',
      caption: a.count == 0
          ? 'Belum ada sesi'
          : a.durationMinutes == null
          ? 'Durasi belum diketahui'
          : '${a.count} sesi${a.reviewCount > 0 ? ' · ${a.reviewCount} perlu ditinjau' : ''}',
      route: a.count == 0 ? Routes.addActivity : Routes.activities,
      push: true,
    ),
    (
      style: DomainStyle.medication,
      label: 'Obat',
      value: med == null || med.scheduled == 0
          ? null
          : '${med.taken + med.skipped} dari ${med.scheduled}',
      caption: medication.hasError && med == null
          ? 'Belum dapat dimuat'
          : med == null
          ? 'Memuat…'
          : med.scheduled == 0
          ? 'Belum ada jadwal obat'
          : med.unknown > 0
          ? 'Jadwal dikonfirmasi · ${med.unknown} belum'
          : 'Jadwal dikonfirmasi',
      route: Routes.medications,
      push: true,
    ),
  ];
}

class DaySummaryCard extends StatelessWidget {
  const DaySummaryCard({
    super.key,
    required this.data,
    required this.medication,
  });
  final DailyInsights data;
  final AsyncValue<MedicationToday?> medication;

  @override
  Widget build(BuildContext context) {
    final rows = dayRows(data, medication);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg - 2),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              _DayRowTile(row: rows[i]),
              if (i < rows.length - 1)
                Divider(
                  height: 1,
                  indent: 66,
                  endIndent: 16,
                  color: AppColors.border,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DayRowTile extends StatelessWidget {
  const _DayRowTile({required this.row});
  final DayRow row;

  @override
  Widget build(BuildContext context) {
    final r = row;
    return Semantics(
      button: true,
      label: '${r.label}: ${r.value ?? ''} ${r.caption}',
      excludeSemantics: true,
      onTap: () => context.push(r.route),
      child: InkWell(
        onTap: () => context.push(r.route),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Container(
                height: 36,
                width: 36,
                decoration: BoxDecoration(
                  color: r.style.tint,
                  shape: BoxShape.circle,
                ),
                child: Icon(r.style.icon, size: 19, color: r.style.ink),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.label, style: AppTypography.secondaryStrong),
                    if (r.value != null)
                      Text(r.value!, style: AppTypography.title),
                    Text(r.caption, style: AppTypography.caption),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.decorative),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlucoseDayChart extends ConsumerWidget {
  const _GlucoseDayChart({required this.date, required this.isToday});
  final String date;
  final bool isToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glucose = ref
        .watch(glucosePageProvider((cursor: null, date: date, archived: false)))
        .value;
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
    if (points.isEmpty) return const SizedBox.shrink();
    final unit = glucose?.displayUnit ?? 'mg/dL';
    return ChartCard(
      icon: DomainStyle.glucose.icon,
      tint: DomainStyle.glucose.tint,
      ink: DomainStyle.glucose.ink,
      title: '${isToday ? 'Glukosa hari ini' : 'Glukosa hari itu'} ($unit)',
      caption:
          'Satu titik satu pengukuran, tidak dihubungkan. Lingkaran kosong: perlu ditinjau.',
      child: DotPlot(
        points: points,
        unit: unit,
        color: AppColors.glucoseInk,
        semanticLabel: 'Grafik titik glukosa. ${points.length} pengukuran.',
      ),
    );
  }
}
