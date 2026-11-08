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
import '../../../core/widgets/health_card.dart';
import '../application/today_controller.dart';
import '../../nutrition/data/nutrition_models.dart';
import '../../nutrition/presentation/nutrition_widgets.dart';
import '../../quick_record/presentation/quick_record_sheet.dart';

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
                        'Catat makanan dan pengukuran glukosa hari ini. Setiap catatan tetap dalam kendalimu.',
                        style: AppTypography.body.copyWith(
                          color: AppColors.onPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                PillButton(
                  label: 'Quick Record',
                  icon: Icons.add_rounded,
                  onPressed: () => showQuickRecord(context),
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
                if (today.nutrition != null) ...[
                  NutritionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Nutrisi', style: AppTypography.title),
                        const SizedBox(height: 8),
                        Text(
                          today.nutrition!.mealCount == 0
                              ? 'Belum ada catatan makanan hari ini.'
                              : '${today.nutrition!.mealCount} catatan makanan hari ini.',
                          style: AppTypography.body,
                        ),
                        Text(
                          'Energi: ${today.nutrition!.totals['calories']?.label('kkal') ?? 'Belum tersedia'}',
                          style: AppTypography.secondary,
                        ),
                        Wrap(
                          children: [
                            TextButton(
                              onPressed: () => context.push(Routes.addMeal),
                              child: const Text('Catat makanan'),
                            ),
                            TextButton(
                              onPressed: () => context.push(Routes.meals),
                              child: const Text('Histori makanan'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                HealthCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Glukosa', style: AppTypography.title),
                      const SizedBox(height: 8),
                      Text(
                        today.glucose?.latest?.label ??
                            'Belum ada pengukuran hari ini.',
                        style: AppTypography.heading,
                      ),
                      if (today.glucose?.latest case final record?) ...[
                        Text('${record.localTime} · glukometer manual'),
                        Text(
                          record.qualityLabel,
                          style: AppTypography.secondary,
                        ),
                      ],
                      Wrap(
                        children: [
                          TextButton(
                            onPressed: () => context.push(Routes.addGlucose),
                            child: const Text('Catat glukosa'),
                          ),
                          TextButton(
                            onPressed: () => context.push(Routes.glucose),
                            child: const Text('Riwayat glukosa'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                for (final item in [
                  if (today.nutrition == null)
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
                if (today.events.isNotEmpty) ...[
                  Text('Catatan hari ini', style: AppTypography.heading),
                  for (final event in today.events)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${event.domain == 'meal' ? mealCategories[event.category] : 'Glukosa'} · ${event.localTime}',
                      ),
                      subtitle: Text(
                        event.domain == 'meal'
                            ? '${event.itemCount} item makanan'
                            : '${event.displayValue} ${event.displayUnit} · glukometer manual${event.qualityStatus == 'needs_review' ? ' · perlu ditinjau' : ''}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(
                        '${event.domain == 'meal' ? Routes.meals : Routes.glucose}/${event.recordId}',
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
                const InfoCard(
                  title: 'Tujuan personal',
                  text: 'Pelacakan tujuan belum tersedia.',
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
