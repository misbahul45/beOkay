import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/format/formatters.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/detail_kit.dart';
import '../../../core/widgets/domain_style.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../today/application/today_controller.dart';
import '../application/nutrition_controller.dart';
import '../data/nutrition_models.dart';
import 'meal_form_screen.dart';
import 'nutrition_widgets.dart';
import 'meal_context_section.dart';
import 'record_reason_dialog.dart';

class MealDetailScreen extends ConsumerStatefulWidget {
  const MealDetailScreen({super.key, required this.id, this.edit = false});
  final String id;
  final bool edit;
  @override
  ConsumerState<MealDetailScreen> createState() => _MealDetailScreenState();
}

class _MealDetailScreenState extends ConsumerState<MealDetailScreen> {
  bool busy = false;
  String? error;
  Future<void> archive(MealRecord meal) async {
    final explanation = await showDialog<String>(
      context: context,
      builder: (_) => RecordReasonDialog(restoring: meal.archived),
    );
    if (explanation == null || !mounted) return;
    final repo = ref.read(nutritionRepositoryProvider);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await repo.save({
        'expectedVersion': meal.version,
        'reason': explanation,
        'archived': !meal.archived,
      }, id: meal.id);
      if (mounted && repo.isCurrentAccount()) {
        ref.invalidate(mealProvider(meal.id));
        ref.invalidate(todayProvider);
        ref.invalidate(mealPageProvider);
      }
    } catch (e) {
      if (mounted) setState(() => error = messageFor(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(mealProvider(widget.id));
    return value.when(
      skipLoadingOnRefresh: false,
      skipLoadingOnReload: false,
      loading: () => const PageScaffold(
        title: 'Memuat catatan',
        children: [SkeletonList()],
      ),
      error: (e, _) => PageScaffold(
        title: 'Detail makanan',
        children: [
          NutritionError(
            error: e,
            retry: () => ref.invalidate(mealProvider(widget.id)),
          ),
        ],
      ),
      data: (meal) {
        if (widget.edit) return MealFormScreen(initial: meal);
        final kcal = meal.totals['calories'];
        final itemsLabel = '${meal.items.length} makanan';
        return PageScaffold(
          title: mealCategories[meal.category],
          onBack: () =>
              context.canPop() ? context.pop() : context.go(Routes.meals),
          actions: [
            IconButton(
              tooltip: 'Beranda',
              onPressed: () => context.go(Routes.home),
              icon: const Icon(Icons.home_outlined),
            ),
          ],
          children: [
            DetailHero(
              style: DomainStyle.meal,
              eyebrow: '${mealCategories[meal.category]} · $itemsLabel',
              value: kcal?.value == null
                  ? '–'
                  : kcal!.value!.round().toString(),
              unit: kcal?.value == null
                  ? 'energi belum tersedia'
                  : 'kkal tercatat',
              archived: meal.archived,
              chips: [
                '${meal.localDate} · ${meal.localTime}',
                'Dilaporkan sendiri',
                if (revisionLabel(meal.version, archived: false).isNotEmpty)
                  revisionLabel(meal.version, archived: false),
              ],
            ),
            DetailSection(
              title: 'Makanan',
              children: [
                for (final (index, item) in meal.items.indexed) ...[
                  if (index > 0) Divider(height: 16, color: AppColors.border),
                  Text(item.name, style: AppTypography.bodyStrong),
                  Text(
                    '${item.quantity} ${portionUnits[item.unit] ?? item.unit}${item.unit != 'g' && item.grams != null ? ' · ${item.grams} g' : ''}',
                    style: AppTypography.body,
                  ),
                  Text(
                    [
                      item.source == 'user_reported'
                          ? 'Dilaporkan sendiri'
                          : item.source,
                      item.status == 'unknown'
                          ? 'Nilai gizi belum tersedia'
                          : item.status == 'estimated'
                          ? 'Estimasi'
                          : 'Referensi dilaporkan pengguna',
                      if (item.gramsBasis == 'user_estimate') 'berat perkiraan',
                    ].join(' · '),
                    style: AppTypography.caption,
                  ),
                ],
              ],
            ),
            DetailSection(
              title: 'Ringkasan gizi',
              children: [NutritionTotals(totals: meal.totals)],
            ),
            if (!meal.archived) MealContextSection(id: meal.id),
            if (meal.notes != null)
              DetailSection(
                title: 'Catatan',
                children: [Text(meal.notes!, style: AppTypography.body)],
              ),
            DetailActions(
              children: [
                if (!meal.archived)
                  PillButton(
                    label: 'Koreksi catatan',
                    icon: Icons.edit_outlined,
                    kind: PillButtonKind.secondary,
                    expand: false,
                    onPressed: busy
                        ? null
                        : () => context.push('${Routes.meals}/${meal.id}/edit'),
                  ),
                PillButton(
                  label: meal.archived
                      ? 'Pulihkan catatan'
                      : 'Arsipkan catatan',
                  icon: meal.archived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                  kind: PillButtonKind.secondary,
                  expand: false,
                  loading: busy,
                  onPressed: () => archive(meal),
                ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              ErrorBanner(error!),
            ],
            DetailSection(
              title: 'Riwayat koreksi',
              children: [
                ref
                    .watch(mealRevisionsProvider(meal.id))
                    .when(
                      skipLoadingOnRefresh: false,
                      skipLoadingOnReload: false,
                      loading: () => const SkeletonList(rows: 1),
                      error: (e, _) => NutritionError(
                        error: e,
                        retry: () =>
                            ref.invalidate(mealRevisionsProvider(meal.id)),
                      ),
                      data: (items) => RevisionTimeline(
                        entries: [
                          for (final item in items)
                            RevisionEntry(
                              version: item['version'] as int,
                              reason: '${item['reason']}',
                              createdAt: '${item['createdAt']}',
                              before: item['snapshot'] is Map
                                  ? [
                                      for (final old
                                          in ((item['snapshot'] as Map)['items']
                                                  as List? ??
                                              const []))
                                        '${old['name']}: ${old['quantity']} ${old['unit']}',
                                      'Waktu sebelumnya: ${friendlyStamp('${(item['snapshot'] as Map)['consumedAt']}')}',
                                    ].join('\n')
                                  : null,
                            ),
                        ],
                      ),
                    ),
              ],
            ),
            const SizedBox(height: 12),
            PillButton(
              label: 'Lihat histori makanan',
              kind: PillButtonKind.ghost,
              onPressed: () => context.go(Routes.meals),
            ),
          ],
        );
      },
    );
  }
}
