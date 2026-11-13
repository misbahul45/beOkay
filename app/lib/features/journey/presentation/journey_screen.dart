import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/health_card.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../health_profile/application/health_controller.dart';
import '../application/journey_controller.dart';
import '../data/journey_repository.dart';

class JourneyScreen extends ConsumerWidget {
  const JourneyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journey = ref.watch(journeyProvider);
    return PageScaffold(
      title: 'Jalurmu',
      children: [
        AsyncBody<JourneyView>(
          value: journey,
          onRetry: () => ref.invalidate(journeyProvider),
          data: (j) => _JourneyBody(journey: j),
        ),
      ],
    );
  }
}

class _JourneyBody extends ConsumerWidget {
  const _JourneyBody({required this.journey});

  final JourneyView journey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = journey.capabilities;
    final items = [
      ('Rencana kecil dan Asisten', c.coaching && c.assistant),
      if (journey.journey == 'PREVENTION')
        ('Bacaan pencegahan dan pemeriksaan rutin', true),
      ('Komunitas dan tantangan', c.community),
      (
        c.glucoseVisible
            ? 'Glukosa dan obat'
            : 'Glukosa dan obat (bisa dinyalakan di Catat)',
        c.glucoseVisible,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HealthCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('JALUR SAAT INI', style: AppTypography.overline),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      journey.label,
                      style: AppTypography.secondaryStrong.copyWith(
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ),
                  Text(
                    journey.assumed
                        ? 'belum diisi di profil kesehatan'
                        : 'dari pernyataanmu',
                    style: AppTypography.caption,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(journey.description, style: AppTypography.body),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        HealthCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('YANG TERSEDIA UNTUKMU', style: AppTypography.overline),
              const SizedBox(height: AppSpacing.xs),
              for (final (label, on) in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        on ? Icons.check_rounded : Icons.remove_rounded,
                        size: 18,
                        color: on ? AppColors.brand : AppColors.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          label,
                          style: on
                              ? AppTypography.body
                              : AppTypography.body.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const InfoCard(
          tone: InfoTone.neutral,
          title: 'Bila jalur tidak cocok',
          text:
              'Untuk diabetes tipe 1, usia di bawah 18, atau usia belum diisi, beOkay hanya membantu mencatat. Saran belum tersedia.',
        ),
        const SizedBox(height: AppSpacing.md),
        PillButton(
          label: 'Ubah jawaban',
          kind: PillButtonKind.secondary,
          onPressed: () async {
            await context.push(Routes.editHealth);
            ref.invalidate(journeyProvider);
            ref.invalidate(healthControllerProvider);
          },
        ),
      ],
    );
  }
}
