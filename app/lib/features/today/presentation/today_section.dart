import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/domain_style.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/metric_card.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/timeline_tile.dart';
import '../../goals/application/goals_controller.dart';
import '../../medication/application/medication_controller.dart';
import '../application/today_controller.dart';
import 'today_extras.dart';

/// Domain cards and recent events. Header and Quick Record live in HomeScreen.
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
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: false,
          loading: () => const SkeletonList(),
          error: (error, _) {
            if (error is ApiException && error.code == 'CONSENT_REQUIRED') {
              return InfoCard(
                title: 'Persetujuan diperlukan',
                text: 'Tinjau persetujuan untuk membuka ringkasan kesehatan.',
                action: PillButton(
                  label: 'Kelola persetujuan',
                  expand: false,
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
            final glucose = today.glucose;
            final nutrition = today.nutrition;
            final activity = today.activity;
            final calories = nutrition?.totals['calories'];
            final latest = glucose?.latest;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text('Hari ini', style: AppTypography.heading),
                ),
                const SizedBox(height: AppSpacing.xs + 2),
                MetricCard(
                  icon: DomainStyle.glucose.icon,
                  tint: DomainStyle.glucose.tint,
                  ink: DomainStyle.glucose.ink,
                  title: 'Glukosa',
                  badge:
                      latest != null && latest.qualityStatus == 'needs_review'
                      ? const StatusBadge(
                          label: 'Perlu ditinjau',
                          tone: InfoTone.warning,
                        )
                      : null,
                  value: latest?.label,
                  valueCaption: latest == null
                      ? null
                      : 'Pukul ${latest.localTime} · glukometer manual',
                  emptyMessage: 'Belum ada pengukuran.',
                  primaryLabel: 'Catat glukosa',
                  onPrimary: () => context.push(Routes.addGlucose),
                  secondaryLabel: 'Riwayat glukosa',
                  onSecondary: () => context.push(Routes.glucose),
                ),
                if (nutrition != null) ...[
                  const SizedBox(height: 10),
                  MetricCard(
                    icon: DomainStyle.meal.icon,
                    tint: DomainStyle.meal.tint,
                    ink: DomainStyle.meal.ink,
                    title: 'Nutrisi',
                    value: nutrition.mealCount == 0
                        ? null
                        : '${nutrition.mealCount} catatan makan',
                    emptyMessage: 'Belum ada catatan makan.',
                    details: [
                      if (nutrition.mealCount > 0)
                        'Energi: ${calories?.label('kkal') ?? 'Belum tersedia'}',
                    ],
                    primaryLabel: 'Catat makanan',
                    onPrimary: () => context.push(Routes.addMeal),
                    secondaryLabel: 'Riwayat makanan',
                    onSecondary: () => context.push(Routes.meals),
                  ),
                ],
                if (activity != null) ...[
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
                    value: activity.count == 0
                        ? null
                        : '${activity.durationMinutes ?? 0} menit',
                    valueCaption: activity.count == 0
                        ? null
                        : '${activity.count} sesi hari ini',
                    emptyMessage: 'Belum ada sesi.',
                    primaryLabel: 'Catat aktivitas',
                    onPrimary: () => context.push(Routes.addActivity),
                    secondaryLabel: 'Riwayat aktivitas',
                    onSecondary: () => context.push(Routes.activities),
                  ),
                ],
                const SizedBox(height: 10),
                _MedicationCard(),
                const SizedBox(height: 10),
                _GoalsCard(),
                if (nutrition != null && nutrition.mealCount > 0) ...[
                  const SizedBox(height: AppSpacing.md),
                  NutritionSnapshotCard(nutrition: nutrition),
                ],
                const SizedBox(height: AppSpacing.md),
                TodayActions(mealCount: nutrition?.mealCount),
                const SizedBox(height: AppSpacing.md),
                const CompanionInsightCard(),
                const SizedBox(height: AppSpacing.lg),
                Semantics(
                  header: true,
                  child: Text('Catatan terbaru', style: AppTypography.heading),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (today.events.isEmpty)
                  Text(
                    'Belum ada catatan hari ini. Catatan yang kamu simpan muncul di sini.',
                    style: AppTypography.secondary,
                  )
                else
                  for (final event in today.events) ...[
                    TimelineTile(
                      item: event,
                      onTap: () => context.push(
                        DomainStyle.of(
                          event.domain,
                        ).detailRoute(event.recordId),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                const SizedBox(height: AppSpacing.xs),
                PillButton(
                  label: 'Lihat semua catatan',
                  kind: PillButtonKind.secondary,
                  onPressed: () => context.go(Routes.log),
                ),
                const SizedBox(height: AppSpacing.xs),
                PillButton(
                  label: 'Buka wawasan',
                  kind: PillButtonKind.ghost,
                  onPressed: () => context.go(Routes.insights),
                ),
              ],
            );
          },
        );
  }
}

class _MedicationCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(medicationTodayProvider).value;
    final empty = today == null || today.scheduled == 0;
    return MetricCard(
      icon: DomainStyle.medication.icon,
      tint: DomainStyle.medication.tint,
      ink: DomainStyle.medication.ink,
      title: 'Obat',
      value: empty
          ? null
          : '${today.taken + today.skipped} dari ${today.scheduled} dikonfirmasi',
      valueCaption: empty || today.unknown == 0
          ? null
          : '${today.unknown} belum dikonfirmasi',
      emptyMessage: 'Belum ada jadwal hari ini.',
      primaryLabel: 'Tambah obat',
      onPrimary: () => context.push(Routes.addMedication),
      secondaryLabel: 'Buka obat',
      onSecondary: () => context.push(Routes.medications),
    );
  }
}

class _GoalsCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals =
        ref
            .watch(goalsListProvider)
            .value
            ?.where((g) => g.status == 'active')
            .toList() ??
        const [];
    return MetricCard(
      icon: DomainStyle.goal.icon,
      tint: DomainStyle.goal.tint,
      ink: DomainStyle.goal.ink,
      title: 'Tujuan personal',
      value: goals.isEmpty ? null : '${goals.length} tujuan aktif',
      valueCaption: goals.isEmpty
          ? null
          : goals.take(2).map((g) => g.title).join(' · '),
      emptyMessage: 'Belum ada tujuan.',
      primaryLabel: 'Buat tujuan',
      onPrimary: () => context.push(Routes.addGoal),
      secondaryLabel: 'Buka tujuan',
      onSecondary: () => context.push(Routes.goals),
    );
  }
}
