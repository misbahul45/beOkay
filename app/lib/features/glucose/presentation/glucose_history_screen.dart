import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/format/formatters.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/health_card.dart';
import '../../../core/widgets/health_error.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../application/glucose_controller.dart';
import '../data/glucose_models.dart';
import 'glucose_chart.dart';

class GlucoseHistoryScreen extends ConsumerStatefulWidget {
  const GlucoseHistoryScreen({super.key});
  @override
  ConsumerState<GlucoseHistoryScreen> createState() =>
      _GlucoseHistoryScreenState();
}

class _GlucoseHistoryScreenState extends ConsumerState<GlucoseHistoryScreen> {
  String? date;
  bool archived = false;
  List<String?> cursors = [null];
  @override
  Widget build(BuildContext context) {
    ref.listen(
      glucoseRepositoryProvider,
      (_, _) => setState(() => cursors = [null]),
    );
    final query = (cursor: cursors.last, date: date, archived: archived);
    return PageScaffold(
      title: 'Riwayat glukosa',
      onBack: () => context.go(Routes.home),
      children: [
        PillButton(
          label: 'Catat glukosa',
          onPressed: () => context.push(Routes.addGlucose),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => context.push(Routes.settings),
          child: const Text('Ubah satuan tampilan'),
        ),
        Wrap(
          spacing: 8,
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
              onSelected: (v) => setState(() {
                archived = v;
                cursors = [null];
              }),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (!archived)
          ref
              .watch(glucoseDayProvider(date))
              .when(
                skipLoadingOnRefresh: false,
                skipLoadingOnReload: false,
                loading: () => const SkeletonList(rows: 1),
                error: (e, _) => HealthError(
                  error: e,
                  retry: () => ref.invalidate(glucoseDayProvider(date)),
                ),
                data: (day) => HealthCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        date == null ? 'Ringkasan hari ini' : 'Ringkasan $date',
                        style: AppTypography.title,
                      ),
                      Text(
                        '${day.count} pengukuran · ${day.reviewCount} perlu ditinjau',
                        style: AppTypography.secondary,
                      ),
                      Text(
                        day.mean == null
                            ? 'Rata-rata belum tersedia: perlu minimal 2 pengukuran.'
                            : 'Rata-rata ${day.mean} ${day.displayUnit} · min ${day.minimum} · maks ${day.maximum}',
                        style: AppTypography.secondary,
                      ),
                      ExpansionTile(
                        title: const Text('Metode dan sumber'),
                        children: [
                          Text(
                            'Dari ${day.eligibleCount} pengukuran glukometer manual yang kamu catat. Rata-rata biasa dari nilai yang dilaporkan; konversi 18,016 mg/dL per mmol/L.\n${updatedAtLabel(day.computedAt)}',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
        const SizedBox(height: 16),
        ref
            .watch(glucosePageProvider(query))
            .when(
              skipLoadingOnRefresh: false,
              skipLoadingOnReload: false,
              loading: () => const SkeletonList(),
              error: (e, _) => HealthError(
                error: e,
                retry: () => ref.invalidate(glucosePageProvider(query)),
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
                          : 'Belum ada pengukuran',
                      text:
                          'Catat hasil glukometer dan satuan yang tertera pada alat.',
                    ),
                  if (!archived)
                    GlucoseChart(items: page.items, unit: page.displayUnit),
                  for (final record in page.items)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: HealthCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(record.label, style: AppTypography.heading),
                            Text(
                              '${record.localDate} · ${record.localTime} · ${glucoseContexts[record.mealContext]}',
                            ),
                            Text(
                              'Glukometer manual · ${record.qualityLabel}',
                              style: AppTypography.secondary,
                            ),
                            TextButton(
                              onPressed: () => context.push(
                                '${Routes.glucose}/${record.id}',
                              ),
                              child: const Text('Lihat pengukuran'),
                            ),
                          ],
                        ),
                      ),
                    ),
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
                    onPressed: () {
                      ref.invalidate(glucosePageProvider(query));
                      ref.invalidate(glucoseDayProvider(date));
                    },
                    child: const Text('Muat ulang riwayat'),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
