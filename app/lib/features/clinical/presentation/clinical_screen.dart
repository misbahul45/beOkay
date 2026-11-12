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
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../application/clinical_controller.dart';
import '../data/clinical_models.dart';

String friendlyDate(String isoDate) =>
    DateFormat('d MMM yyyy', 'id_ID').format(DateTime.parse(isoDate));

class ClinicalScreen extends ConsumerWidget {
  const ClinicalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(clinicalSummaryProvider);
    return PageScaffold(
      title: 'Ukuran tubuh & hasil lab',
      onRefresh: () async => ref.invalidate(clinicalSummaryProvider),
      children: [
        value.when(
          loading: () => const SkeletonList(rows: 4),
          error: (e, _) => e is ApiException && e.code == 'CONSENT_REQUIRED'
              ? InfoCard(
                  tone: InfoTone.warning,
                  title: 'Persetujuan diperlukan',
                  text:
                      'Ringkasan ini memakai persetujuan mencatat data kesehatan dan membuat ringkasan deskriptif.',
                  action: PillButton(
                    label: 'Kelola persetujuan',
                    expand: false,
                    onPressed: () => context.push(Routes.consentManagement),
                  ),
                )
              : ErrorState(
                  error: e,
                  onRetry: () => ref.invalidate(clinicalSummaryProvider),
                ),
          data: (s) => _Body(summary: s),
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.summary});
  final ClinicalSummary summary;

  @override
  Widget build(BuildContext context) {
    final h = summary.hba1c;
    final labs = summary.labs
        .where((l) => l.latest != null && l.test != 'hba1c')
        .toList();
    final hba1c = summary.labs.firstWhere((l) => l.test == 'hba1c');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoCard(tone: InfoTone.neutral, text: summary.notice),
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text('HbA1c', style: AppTypography.heading),
        ),
        const SizedBox(height: AppSpacing.xs),
        _Row(
          title: hba1c.latest?.display ?? 'Belum ada catatan',
          subtitle: hba1c.latest == null
              ? 'Catat hasil HbA1c dari lembar hasil labmu.'
              : [
                  'Sampel ${friendlyDate(hba1c.latest!.sampledAt)}',
                  if (hba1c.change != null)
                    hba1c.change!.text(hba1c.latest!.unit),
                  if (h.due) 'sudah ${h.daysSince} hari',
                ].join(' · '),
          highlight: h.due,
          onTap: hba1c.latest == null
              ? () => context.push('${Routes.addLab}?test=hba1c')
              : () => context.push('${Routes.clinical}/labs/history/hba1c'),
        ),
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text('Ukuran tubuh', style: AppTypography.heading),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final v in summary.vitals)
          _Row(
            title: v.label,
            value: v.latest?.display,
            subtitle: v.latest == null
                ? 'Belum ada catatan'
                : [
                    '${friendlyDate(v.latest!.localDate)} · ${v.latest!.localTime}',
                    if (v.change != null) v.change!.text(v.latest!.unit),
                  ].join(' · '),
            onTap: v.latest == null
                ? () => context.push('${Routes.addVital}?kind=${v.kind}')
                : () => context.push(
                    '${Routes.clinical}/vitals/history/${v.kind}',
                  ),
          ),
        const SizedBox(height: AppSpacing.sm),
        PillButton(
          label: 'Catat ukuran tubuh',
          icon: Icons.add,
          kind: PillButtonKind.secondary,
          onPressed: () => context.push(Routes.addVital),
        ),
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text('Hasil lab lain', style: AppTypography.heading),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (labs.isEmpty)
          Text('Belum ada hasil lab lain.', style: AppTypography.secondary)
        else
          for (final l in labs)
            _Row(
              title: l.label,
              value: l.latest!.display,
              subtitle: [
                'Sampel ${friendlyDate(l.latest!.sampledAt)}',
                if (l.change != null) l.change!.text(l.latest!.unit),
              ].join(' · '),
              onTap: () =>
                  context.push('${Routes.clinical}/labs/history/${l.test}'),
            ),
        const SizedBox(height: AppSpacing.sm),
        PillButton(
          label: 'Catat hasil lab',
          icon: Icons.add,
          kind: PillButtonKind.secondary,
          onPressed: () => context.push(Routes.addLab),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.subtitle,
    this.value,
    this.onTap,
    this.highlight = false,
  });
  final String title, subtitle;
  final String? value;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Material(
      color: highlight ? AppColors.warningBackground : AppColors.surface,
      borderRadius: AppRadius.cardRadius,
      child: InkWell(
        borderRadius: AppRadius.cardRadius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.bodyStrong),
                    if (value != null) Text(value!, style: AppTypography.title),
                    Text(subtitle, style: AppTypography.caption),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.decorative),
            ],
          ),
        ),
      ),
    ),
  );
}
