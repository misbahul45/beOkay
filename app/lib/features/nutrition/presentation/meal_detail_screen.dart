import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../today/application/today_controller.dart';
import '../application/nutrition_controller.dart';
import '../data/nutrition_models.dart';
import 'meal_form_screen.dart';
import 'nutrition_widgets.dart';
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
            Text(
              '${meal.localDate} · ${meal.localTime}',
              style: AppTypography.headline,
            ),
            Text(meal.timezone, style: AppTypography.secondary),
            const SizedBox(height: 12),
            Text(
              'Dilaporkan sendiri · versi ${meal.version}${meal.archived ? ' · diarsipkan' : ''}',
              style: AppTypography.secondary,
            ),
            const SizedBox(height: 24),
            for (final item in meal.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: NutritionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, style: AppTypography.title),
                      Text(
                        '${item.quantity} ${portionUnits[item.unit] ?? item.unit}${item.unit != 'g' && item.grams != null ? ' · ${item.grams} g' : ''}',
                        style: AppTypography.body,
                      ),
                      Text(
                        'Sumber: ${item.source == 'user_reported' ? 'Dilaporkan sendiri' : item.source}',
                        style: AppTypography.secondary,
                      ),
                      Text(
                        item.status == 'unknown'
                            ? 'Nilai gizi belum tersedia'
                            : item.status == 'estimated'
                            ? 'Estimasi'
                            : 'Referensi dilaporkan pengguna',
                        style: AppTypography.secondary,
                      ),
                      if (item.gramsBasis == 'user_estimate')
                        const Text('Berat merupakan perkiraan pengguna.'),
                    ],
                  ),
                ),
              ),
            NutritionTotals(totals: meal.totals),
            const SizedBox(height: 16),
            if (meal.notes != null)
              Text(meal.notes!, style: AppTypography.body),
            const SizedBox(height: 16),
            if (error != null) ErrorBanner(error!),
            if (!meal.archived)
              PillButton(
                label: 'Koreksi catatan',
                kind: PillButtonKind.secondary,
                onPressed: busy
                    ? null
                    : () => context.push('${Routes.meals}/${meal.id}/edit'),
              ),
            const SizedBox(height: 12),
            PillButton(
              label: meal.archived ? 'Pulihkan catatan' : 'Arsipkan catatan',
              kind: PillButtonKind.secondary,
              loading: busy,
              onPressed: () => archive(meal),
            ),
            const SizedBox(height: 24),
            Text('Riwayat koreksi', style: AppTypography.heading),
            const SizedBox(height: 12),
            ref
                .watch(mealRevisionsProvider(meal.id))
                .when(
                  skipLoadingOnRefresh: false,
                  skipLoadingOnReload: false,
                  loading: () => const SkeletonList(rows: 1),
                  error: (e, _) => NutritionError(
                    error: e,
                    retry: () => ref.invalidate(mealRevisionsProvider(meal.id)),
                  ),
                  data: (items) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (items.isEmpty) const Text('Belum ada koreksi.'),
                      for (final item in items)
                        ExpansionTile(
                          title: Text(
                            'Versi ${item['version']} · ${item['reason']}',
                          ),
                          subtitle: Text(item['createdAt'] as String),
                          children: [
                            if (item['snapshot'] is Map)
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (final old
                                        in ((item['snapshot'] as Map)['items']
                                            as List))
                                      Text(
                                        '${old['name']}: ${old['quantity']} ${old['unit']}',
                                      ),
                                    Text(
                                      'Waktu sebelumnya: ${(item['snapshot'] as Map)['consumedAt']}',
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
            const SizedBox(height: 24),
            PillButton(
              label: 'Lihat histori makanan',
              kind: PillButtonKind.secondary,
              onPressed: () => context.go(Routes.meals),
            ),
          ],
        );
      },
    );
  }
}
