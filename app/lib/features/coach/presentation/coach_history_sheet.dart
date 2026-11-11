import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/ids/record_id.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/pill_button.dart';
import '../application/coach_controller.dart';
import '../application/conversation_controller.dart';
import '../data/coach_repository.dart';

Future<void> showCoachHistory(BuildContext context) {
  FocusManager.instance.primaryFocus?.unfocus();
  return _showHistory(context);
}

Future<void> _showHistory(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: AppColors.background,
  builder: (_) => const _HistorySheet(),
);

String _when(DateTime? t) {
  if (t == null) return '';
  final now = DateTime.now();
  final sameDay =
      t.year == now.year && t.month == now.month && t.day == now.day;
  return sameDay
      ? DateFormat('HH:mm', 'id_ID').format(t)
      : DateFormat('d MMM', 'id_ID').format(t);
}

class _HistorySheet extends ConsumerWidget {
  const _HistorySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threads = ref.watch(conversationThreadsProvider);
    final current = ref.watch(conversationControllerProvider).threadId;
    final controller = ref.read(conversationControllerProvider.notifier);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            0,
            AppSpacing.page,
            AppSpacing.lg,
          ),
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: AppSpacing.xs,
              spacing: AppSpacing.xs,
              children: [
                Semantics(
                  header: true,
                  child: Text('Percakapan', style: AppTypography.heading),
                ),
                PillButton(
                  label: 'Percakapan baru',
                  icon: Icons.add_rounded,
                  kind: PillButtonKind.secondary,
                  expand: false,
                  onPressed: () {
                    controller.startNew();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            threads.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(),
              ),
              error: (_, _) => Text(
                'Riwayat tidak dapat dimuat.',
                style: AppTypography.secondary,
              ),
              data: (items) => items.isEmpty
                  ? Text(
                      'Belum ada percakapan tersimpan.',
                      style: AppTypography.secondary,
                    )
                  : Column(
                      children: [
                        for (final t in items)
                          _ThreadTile(
                            title: t.title ?? 'Percakapan',
                            subtitle: _when(t.lastMessageAt),
                            selected: t.id == current,
                            onOpen: () async {
                              Navigator.of(context).pop();
                              await controller.open(t.id);
                            },
                            onDelete: () => _confirmDelete(context, ref, t.id),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Semantics(
              header: true,
              child: Text('Rencana makan', style: AppTypography.title),
            ),
            const SizedBox(height: AppSpacing.xs),
            ref
                .watch(plannedMealsProvider)
                .when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => Text(
                    'Rencana tidak dapat dimuat.',
                    style: AppTypography.secondary,
                  ),
                  data: (items) => items.isEmpty
                      ? Text(
                          'Belum ada. Rencana bukan catatan makan; catat konsumsi sebenarnya di Catatan.',
                          style: AppTypography.secondary,
                        )
                      : Column(
                          children: [
                            for (final p in items) PlannedTile(meal: p),
                          ],
                        ),
                ),
            const SizedBox(height: AppSpacing.lg),
            Semantics(
              header: true,
              child: Text('Rencana aktivitas', style: AppTypography.title),
            ),
            const SizedBox(height: AppSpacing.xs),
            ref
                .watch(activityPlansProvider)
                .when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => Text(
                    'Rencana tidak dapat dimuat.',
                    style: AppTypography.secondary,
                  ),
                  data: (items) => items.isEmpty
                      ? Text(
                          'Belum ada. Rencana bukan catatan aktivitas; catat sesi sebenarnya di Aktivitas.',
                          style: AppTypography.secondary,
                        )
                      : Column(
                          children: [
                            for (final p in items) ActivityPlanTile(plan: p),
                          ],
                        ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Hapus percakapan ini?'),
        content: const Text(
          'Pesan di percakapan ini dihapus. Rencana yang sudah kamu setujui tetap ada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(conversationControllerProvider.notifier).remove(id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(messageFor(e))));
      }
    }
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onOpen,
    required this.onDelete,
  });
  final String title, subtitle;
  final bool selected;
  final VoidCallback onOpen, onDelete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: selected ? AppColors.brandTint : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.bodyStrong,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty)
                      Text(subtitle, style: AppTypography.caption),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Hapus percakapan',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class PlannedTile extends ConsumerWidget {
  const PlannedTile({super.key, required this.meal});
  final PlannedMeal meal;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: AppColors.surface,
      borderRadius: AppRadius.cardRadius,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(meal.name, style: AppTypography.bodyStrong),
            Text(
              '${meal.statusLabel} · ${meal.source}',
              style: AppTypography.caption,
            ),
            if (meal.measuredKind != null)
              Text(
                'Terbukti: makanan serupa tercatat di catatan makanmu.',
                style: AppTypography.caption,
              ),
            if (meal.status == 'PLANNED')
              Wrap(
                children: [
                  TextButton(
                    onPressed: () => _fb(context, ref, true),
                    child: const Text('Sudah dimakan'),
                  ),
                  TextButton(
                    onPressed: () => _fb(context, ref, false),
                    child: const Text('Tidak jadi'),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );

  Future<void> _fb(BuildContext context, WidgetRef ref, bool consumed) async {
    try {
      await ref
          .read(coachRepositoryProvider)
          .feedback(
            meal.recommendationId,
            consumed: consumed,
            operationId: newRecordId(),
          );
      ref.invalidate(plannedMealsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(messageFor(e))));
      }
    }
  }
}

class ActivityPlanTile extends ConsumerWidget {
  const ActivityPlanTile({super.key, required this.plan});
  final ActivityPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: AppColors.surface,
      borderRadius: AppRadius.cardRadius,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${plan.label} ${plan.minutes} menit',
              style: AppTypography.bodyStrong,
            ),
            Text(
              '${plan.statusLabel} · ${plan.plannedFor}',
              style: AppTypography.caption,
            ),
            if (plan.measuredKind != null)
              Text(
                'Terbukti: sesi sejenis tercatat di Aktivitas.',
                style: AppTypography.caption,
              ),
            if (plan.status == 'CONFIRMED')
              Wrap(
                children: [
                  TextButton(
                    onPressed: () => _fb(context, ref, true),
                    child: const Text('Selesai'),
                  ),
                  TextButton(
                    onPressed: () => _fb(context, ref, false),
                    child: const Text('Dilewati'),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );

  Future<void> _fb(BuildContext context, WidgetRef ref, bool completed) async {
    try {
      await ref
          .read(coachRepositoryProvider)
          .activityFeedback(
            plan.recommendationId,
            completed: completed,
            operationId: newRecordId(),
          );
      ref.invalidate(activityPlansProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(messageFor(e))));
      }
    }
  }
}
