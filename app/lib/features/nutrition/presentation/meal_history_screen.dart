import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../application/nutrition_controller.dart';
import '../data/nutrition_models.dart';
import 'nutrition_widgets.dart';

class MealHistoryScreen extends ConsumerStatefulWidget {
  const MealHistoryScreen({super.key});
  @override
  ConsumerState<MealHistoryScreen> createState() => _MealHistoryScreenState();
}

class _MealHistoryScreenState extends ConsumerState<MealHistoryScreen> {
  String? date;
  bool archived = false;
  List<String?> cursors = [null];
  @override
  Widget build(BuildContext context) {
    ref.listen(
      nutritionRepositoryProvider,
      (_, _) => setState(() => cursors = [null]),
    );
    final query = (cursor: cursors.last, date: date, archived: archived);
    return PageScaffold(
      title: 'Riwayat makanan',
      onBack: () => context.go(Routes.home),
      children: [
        PillButton(
          label: 'Catat makanan',
          onPressed: () => context.push(Routes.addMeal),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: () async {
                final chosen = await showDatePicker(
                  context: context,
                  initialDate: date == null
                      ? DateTime.now()
                      : DateTime.parse(date!),
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                );
                if (chosen != null && mounted) {
                  setState(() {
                    date = DateFormat('yyyy-MM-dd').format(chosen);
                    cursors = [null];
                  });
                }
              },
              child: Text(date ?? 'Filter tanggal'),
            ),
            if (date != null)
              TextButton(
                onPressed: () => setState(() {
                  date = null;
                  cursors = [null];
                }),
                child: const Text('Semua tanggal'),
              ),
            FilterChip(
              label: const Text('Arsip'),
              selected: archived,
              onSelected: (value) => setState(() {
                archived = value;
                cursors = [null];
              }),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ref
            .watch(mealPageProvider(query))
            .when(
              skipLoadingOnRefresh: false,
              skipLoadingOnReload: false,
              loading: () => const SkeletonList(),
              error: (e, _) => NutritionError(
                error: e,
                retry: () => ref.invalidate(mealPageProvider(query)),
              ),
              data: (page) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Zona waktu: ${page.timezone}',
                    style: AppTypography.secondary,
                  ),
                  const SizedBox(height: 12),
                  if (page.items.isEmpty)
                    InfoCard(
                      title: archived
                          ? 'Belum ada arsip'
                          : 'Belum ada catatan makanan',
                      text:
                          'Catat nama makanan dan porsinya. Nilai gizi yang belum diketahui tidak diisi otomatis.',
                    ),
                  for (var i = 0; i < page.items.length; i++) ...[
                    if (i == 0 ||
                        page.items[i - 1].localDate != page.items[i].localDate)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          page.items[i].localDate,
                          style: AppTypography.title,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: NutritionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${mealCategories[page.items[i].category]} · ${page.items[i].localTime}',
                              style: AppTypography.title,
                            ),
                            Text(
                              page.items[i].items
                                  .map((item) => item.name)
                                  .join(', '),
                              style: AppTypography.body,
                            ),
                            Text(
                              page.items[i].totals['calories']!.label('kkal'),
                              style: AppTypography.secondary,
                            ),
                            TextButton(
                              onPressed: () => context.push(
                                '${Routes.meals}/${page.items[i].id}',
                              ),
                              child: const Text('Lihat detail'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  Wrap(
                    spacing: 12,
                    children: [
                      if (cursors.length > 1)
                        TextButton(
                          onPressed: () => setState(() => cursors.removeLast()),
                          child: const Text('Sebelumnya'),
                        ),
                      if (page.nextCursor != null)
                        TextButton(
                          onPressed: () =>
                              setState(() => cursors.add(page.nextCursor)),
                          child: const Text('Berikutnya'),
                        ),
                    ],
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(mealPageProvider(query)),
                    child: const Text('Muat ulang histori'),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
