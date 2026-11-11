import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/charts.dart';
import '../../../core/widgets/domain_style.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../preferences/application/preferences_controller.dart';
import '../application/insights_controller.dart';
import '../data/trends.dart';
import 'insight_widgets.dart';
import 'trend_charts.dart';

class TrendsScreen extends ConsumerWidget {
  const TrendsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => PageScaffold(
    title: 'Tren',
    onRefresh: () async {
      ref.invalidate(trendsProvider);
      await ref.read(trendsProvider.future).catchError((_) => null);
    },
    children: const [TrendsBody()],
  );
}

class TrendsBody extends ConsumerWidget {
  const TrendsBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(trendsProvider);
    final unit = ref.watch(effectivePreferencesProvider).glucoseUnit.wire;
    final data = state.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PeriodSelector(),
        const SizedBox(height: AppSpacing.md),
        if (data == null && state.isLoading) const SkeletonList(rows: 3),
        if (state.hasError && data == null)
          _Error(
            error: state.error!,
            onRetry: () => ref.invalidate(trendsProvider),
          ),
        if (data != null)
          if (!data.hasData)
            const InfoCard(
              tone: InfoTone.neutral,
              title: 'Belum ada catatan di rentang ini',
              text: 'Grafik muncul setelah ada catatan.',
            )
          else
            _Sections(data: data, unit: unit, dimmed: state.isLoading),
      ],
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    if (error is ApiException &&
        (error as ApiException).code == 'CONSENT_REQUIRED') {
      return const InfoCard(
        title: 'Persetujuan diperlukan',
        text:
            'Tren memakai data kesehatanmu. Tinjau persetujuan untuk membukanya.',
      );
    }
    return ErrorState(error: error, onRetry: onRetry);
  }
}

String noteText(TrendNote n, int days) => switch (n) {
  StreakNote() =>
    'Kamu mencatat ${n.days} hari berturut-turut. Pertahankan pelan-pelan.',
  ActivityMoreNote() =>
    '${n.current - n.previous} menit aktivitas lebih banyak dari $days hari sebelumnya.',
  PersonalBestNote() =>
    'Hari paling aktifmu di rentang ini: ${DateFormat('EEEE, d MMM', 'id_ID').format(n.date)} (${n.minutes} menit).',
  MoreDaysNote() =>
    'Kamu mencatat di ${n.current} hari, naik dari ${n.previous} hari sebelumnya.',
  UnknownNote() => '',
};

class _Sections extends StatelessWidget {
  const _Sections({
    required this.data,
    required this.unit,
    required this.dimmed,
  });
  final Trends data;
  final String unit;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final t = data;
    final consistencyNotes = t.notes
        .where((n) => n is StreakNote || n is MoreDaysNote)
        .toList();
    final activityNotes = t.notes
        .where((n) => n is ActivityMoreNote || n is PersonalBestNote)
        .toList();
    return Column(
      children: [
        ChartCard(
          icon: DomainStyle.activity.icon,
          tint: DomainStyle.activity.tint,
          ink: DomainStyle.activity.ink,
          title: 'Aktivitas',
          caption:
              'Menit per hari. Abu-abu: periode sebelumnya. – belum ada sesi.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HeroFigure(
                value: t.activityTotal == null
                    ? 'Belum ada sesi'
                    : '${t.activityTotal} menit',
                label: 'Total ${t.days} hari',
                sub: t.activityTotal != null && t.activityPreviousTotal != null
                    ? '${t.days} hari sebelumnya: ${t.activityPreviousTotal} menit'
                    : null,
              ),
              ActivityChart(trends: t, dimmed: dimmed),
              for (final n in activityNotes) _Note(noteText(n, t.days)),
              ChartTableToggle(
                headers: const ['Hari', 'Menit', 'Sebelumnya'],
                rows: activityRows(t),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ChartCard(
          icon: DomainStyle.glucose.icon,
          tint: DomainStyle.glucose.tint,
          ink: DomainStyle.glucose.ink,
          title: 'Glukosa',
          caption: 'Rentang pengukuran per hari ($unit).',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HeroFigure(
                value: t.glucoseReadings == 0
                    ? 'Belum ada pengukuran'
                    : '${t.glucoseReadings} pengukuran',
                label: 'Pada ${t.glucoseDays} dari ${t.days} hari',
              ),
              GlucoseChart(trends: t, unit: unit, dimmed: dimmed),
              ChartTableToggle(
                headers: ['Hari', 'Terendah', 'Tertinggi', 'Jumlah'],
                rows: glucoseRows(t, unit),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ChartCard(
          icon: DomainStyle.meal.icon,
          tint: DomainStyle.meal.tint,
          ink: DomainStyle.meal.ink,
          title: 'Makan',
          caption:
              'Karbohidrat tercatat per hari, dalam gram. Berongga: data gizi sebagian.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HeroFigure(
                value: '${t.mealDays} dari ${t.days} hari',
                label: 'Hari dengan catatan makan',
              ),
              MealChart(trends: t, dimmed: dimmed),
              ChartTableToggle(
                headers: const ['Hari', 'Makan', 'Karbo (g)', 'Cakupan'],
                rows: mealRows(t),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ChartCard(
          icon: DomainStyle.medication.icon,
          tint: DomainStyle.medication.tint,
          ink: DomainStyle.medication.ink,
          title: 'Obat',
          caption:
              'Pekat: diminum · berongga: dilewati · – belum dikonfirmasi.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HeroFigure(
                value: '${t.medConfirmed} konfirmasi',
                label: 'Dalam ${t.days} hari',
                sub:
                    '${t.medTakenTotal} diminum · ${t.medSkippedTotal} dilewati',
              ),
              MedicationChart(trends: t, dimmed: dimmed),
              ChartTableToggle(
                headers: const ['Hari', 'Diminum', 'Dilewati'],
                rows: medicationRows(t),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ChartCard(
          icon: Icons.event_available_rounded,
          tint: AppColors.accent,
          ink: AppColors.brand,
          title: 'Konsistensi mencatat',
          caption: 'Kotak kosong: belum ada catatan.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HeroFigure(
                value: '${t.recordedDays} dari ${t.days} hari',
                label: 'Hari dengan catatan',
              ),
              ConsistencyChart(trends: t, dimmed: dimmed),
              for (final n in consistencyNotes) _Note(noteText(n, t.days)),
              ChartTableToggle(
                headers: const ['Hari', 'Catatan', 'Makan', 'Glukosa'],
                rows: consistencyRows(t),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xs),
    child: InfoCard(
      tone: InfoTone.info,
      icon: Icons.trending_up_rounded,
      text: text,
    ),
  );
}
