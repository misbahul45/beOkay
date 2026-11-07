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
import '../../../core/widgets/pill_button.dart';
import '../application/today_controller.dart';

class TodaySection extends ConsumerStatefulWidget {
  const TodaySection({super.key});

  @override
  ConsumerState<TodaySection> createState() => _TodaySectionState();
}

class _TodaySectionState extends ConsumerState<TodaySection>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.invalidate(todayProvider);
  }

  @override
  Widget build(BuildContext context) {
    return ref
        .watch(todayProvider)
        .when(
          skipLoadingOnRefresh: false,
          skipLoadingOnReload: false,
          loading: () => const SkeletonList(),
          error: (error, _) {
            if (error is ApiException && error.code == 'CONSENT_REQUIRED') {
              return InfoCard(
                title: 'Persetujuan diperlukan',
                text: 'Tinjau persetujuan untuk membuka ringkasan kesehatan.',
                action: PillButton(
                  label: 'Kelola persetujuan',
                  onPressed: () => context.push(Routes.consentManagement),
                ),
              );
            }
            return ErrorState(
              error: error,
              onRetry: () => ref.invalidate(todayProvider),
            );
          },
          data: (today) {
            if (today == null) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat(
                    'EEEE, d MMMM y',
                    'id_ID',
                  ).format(DateTime.parse(today.date)),
                  style: AppTypography.secondary,
                ),
                Text(today.timezone, style: AppTypography.caption),
                const SizedBox(height: AppSpacing.xs),
                Text(today.greeting, style: AppTypography.title),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: AppRadius.cardRadius,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Setiap catatan membantu.',
                        style: AppTypography.headline.copyWith(
                          color: AppColors.onPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Mulai dengan hal yang ingin kamu pantau. Fitur pencatatan sedang disiapkan.',
                        style: AppTypography.body.copyWith(
                          color: AppColors.onPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Semantics(
                  header: true,
                  child: Text(
                    'Ringkasan hari ini',
                    style: AppTypography.heading,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final item in [
                  (
                    Icons.water_drop_outlined,
                    'Glukosa',
                    'Preferensi satuan: ${today.glucoseUnit}.',
                  ),
                  (
                    Icons.restaurant_outlined,
                    'Nutrisi',
                    'Pencatatan makanan sedang disiapkan.',
                  ),
                  (
                    Icons.directions_walk_rounded,
                    'Aktivitas',
                    'Pencatatan aktivitas sedang disiapkan.',
                  ),
                  (
                    Icons.medication_outlined,
                    'Obat',
                    'Jadwal dan konfirmasi konsumsi sedang disiapkan.',
                  ),
                ]) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppRadius.cardRadius,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExcludeSemantics(
                          child: Icon(item.$1, color: AppColors.primary),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.$2, style: AppTypography.title),
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                'Belum tersedia',
                                style: AppTypography.secondaryStrong,
                              ),
                              Text(item.$3, style: AppTypography.secondary),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                const SizedBox(height: AppSpacing.sm),
                const InfoCard(
                  title: 'Tujuan dan catatan harian',
                  text: 'Pelacakan tujuan dan riwayat terpadu belum tersedia.',
                  tone: InfoTone.neutral,
                ),
                const SizedBox(height: AppSpacing.sm),
                const InfoCard(
                  title: 'Insight personal',
                  text:
                      'Insight personal akan tersedia ketika data memenuhi syarat analisis.',
                  tone: InfoTone.neutral,
                ),
                const SizedBox(height: AppSpacing.md),
                PillButton(
                  label: 'Muat ulang ringkasan',
                  kind: PillButtonKind.secondary,
                  onPressed: () => ref.invalidate(todayProvider),
                ),
              ],
            );
          },
        );
  }
}
