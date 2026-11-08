import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/choice_chips.dart';
import '../../../core/widgets/health_card.dart';
import '../../../core/widgets/health_error.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../application/activity_controller.dart';
import 'activity_summary_card.dart';

class ActivityWeekScreen extends ConsumerStatefulWidget {
  const ActivityWeekScreen({super.key});
  @override
  ConsumerState<ActivityWeekScreen> createState() => _ActivityWeekState();
}

class _ActivityWeekState extends ConsumerState<ActivityWeekScreen> {
  String? date, selectedDate;
  void shift(String start, int days) => setState(() {
    date = DateFormat(
      'yyyy-MM-dd',
    ).format(DateTime.parse('${start}T00:00:00Z').add(Duration(days: days)));
    selectedDate = null;
  });
  @override
  Widget build(BuildContext context) => PageScaffold(
    title: 'Aktivitas mingguan',
    onBack: () =>
        context.canPop() ? context.pop() : context.go(Routes.activities),
    children: [
      ref
          .watch(activityWeekProvider(date))
          .when(
            skipLoadingOnRefresh: false,
            skipLoadingOnReload: false,
            loading: () => const SkeletonList(),
            error: (e, _) => HealthError(
              error: e,
              retry: () => ref.invalidate(activityWeekProvider(date)),
            ),
            data: (summary) {
              final selected = summary.days.firstWhere(
                (d) => d.date == selectedDate,
                orElse: () => summary.days.first,
              );
              final start = DateTime.parse(summary.startDate);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${summary.startDate} – ${DateFormat('yyyy-MM-dd').format(DateTime.parse('${summary.endDate}T00:00:00Z').subtract(const Duration(days: 1)))}',
                    style: AppTypography.title,
                  ),
                  Text(
                    '${summary.timezone} · awal minggu ${DateFormat('EEEE', 'id_ID').format(start)}',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => shift(summary.startDate, -7),
                        child: const Text('Minggu sebelumnya'),
                      ),
                      TextButton(
                        onPressed: () => shift(summary.startDate, 7),
                        child: const Text('Minggu berikutnya'),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          date = null;
                          selectedDate = null;
                        }),
                        child: const Text('Minggu ini'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ActivitySummaryCard(
                    summary: summary,
                    title: 'Durasi sesi tercatat',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${summary.activeDays} hari dengan sesi yang dapat diringkas',
                    style: AppTypography.body,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final day in summary.days)
                        PillChip(
                          label:
                              '${DateFormat('EEE d', 'id_ID').format(DateTime.parse(day.date))}\n${day.durationMinutes == null ? 'Belum ada durasi' : '${day.durationMinutes} menit'}',
                          selected: selected.date == day.date,
                          onTap: () => setState(() => selectedDate = day.date),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  HealthCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(selected.date, style: AppTypography.title),
                        Text(
                          '${selected.count} sesi · ${selected.reviewCount} perlu ditinjau',
                        ),
                        Text('Jarak: ${selected.distanceKm.label('km')}'),
                        Text('Langkah: ${selected.steps.label('langkah')}'),
                        TextButton(
                          onPressed: () => context.push(
                            '${Routes.activities}?date=${selected.date}',
                          ),
                          child: const Text('Lihat sesi hari ini'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  PillButton(
                    label: 'Catat aktivitas',
                    onPressed: () => context.push(Routes.addActivity),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(activityWeekProvider(date)),
                    child: const Text('Muat ulang ringkasan'),
                  ),
                ],
              );
            },
          ),
    ],
  );
}
