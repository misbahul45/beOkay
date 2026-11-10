import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/health_card.dart';
import '../../../core/widgets/health_error.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../application/activity_controller.dart';
import '../data/activity_models.dart';
import 'activity_summary_card.dart';
import 'device_import_section.dart';

class ActivityHistoryScreen extends ConsumerStatefulWidget {
  const ActivityHistoryScreen({super.key, this.initialDate});
  final String? initialDate;
  @override
  ConsumerState<ActivityHistoryScreen> createState() => _ActivityHistoryState();
}

class _ActivityHistoryState extends ConsumerState<ActivityHistoryScreen> {
  late String? date = widget.initialDate;
  bool archived = false;
  List<String?> cursors = [null];
  @override
  Widget build(BuildContext context) {
    ref.listen(
      activityRepositoryProvider,
      (_, _) => setState(() => cursors = [null]),
    );
    final query = (cursor: cursors.last, date: date, archived: archived);
    return PageScaffold(
      title: 'Riwayat aktivitas',
      onBack: () => context.go(Routes.home),
      children: [
        PillButton(
          label: 'Catat aktivitas',
          onPressed: () => context.push(Routes.addActivity),
        ),
        const SizedBox(height: 12),
        PillButton(
          label: 'Ringkasan mingguan',
          kind: PillButtonKind.secondary,
          onPressed: () => context.push(Routes.activityWeek),
        ),
        const SizedBox(height: 12),
        const DeviceImportSection(),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () async {
                final now = DateTime.now();
                final requested = date == null
                    ? now
                    : DateTime.tryParse(date!) ?? now;
                final initial = requested.isAfter(now)
                    ? now
                    : requested.isBefore(DateTime(1900))
                    ? DateTime(1900)
                    : requested;
                final chosen = await showDatePicker(
                  context: context,
                  initialDate: initial,
                  firstDate: DateTime(1900),
                  lastDate: now,
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
              .watch(activityDayProvider(date))
              .when(
                skipLoadingOnRefresh: false,
                skipLoadingOnReload: false,
                loading: () => const SkeletonList(rows: 1),
                error: (e, _) => HealthError(
                  error: e,
                  retry: () => ref.invalidate(activityDayProvider(date)),
                ),
                data: (s) => ActivitySummaryCard(
                  summary: s,
                  title: date == null ? 'Hari ini' : 'Ringkasan $date',
                ),
              ),
        const SizedBox(height: 16),
        ref
            .watch(activityPageProvider(query))
            .when(
              skipLoadingOnRefresh: false,
              skipLoadingOnReload: false,
              loading: () => const SkeletonList(),
              error: (e, _) => HealthError(
                error: e,
                retry: () => ref.invalidate(activityPageProvider(query)),
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
                          : 'Belum ada sesi aktivitas',
                      text:
                          'Catat jenis aktivitas dan durasinya. Jarak serta langkah dapat dikosongkan bila tidak diketahui.',
                    ),
                  for (final record in page.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: HealthCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              activityTypes[record.activityType] ??
                                  record.activityType,
                              style: AppTypography.title,
                            ),
                            Text(
                              '${record.durationMinutes} menit · ${record.localDate} ${record.localTime}',
                            ),
                            Text(
                              'Manual · ${record.qualityLabel}',
                              style: AppTypography.secondary,
                            ),
                            TextButton(
                              onPressed: () => context.push(
                                '${Routes.activities}/${record.id}',
                              ),
                              child: const Text('Lihat sesi'),
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
                      ref.invalidate(activityPageProvider(query));
                      ref.invalidate(activityDayProvider(date));
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
