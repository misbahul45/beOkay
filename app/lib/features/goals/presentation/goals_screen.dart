import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ids/record_id.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../application/goals_controller.dart';
import '../data/goals_repository.dart';

/// Behavioral goals only: progress counts recorded behavior; missing data is "no records", never "failed".
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      ref.invalidate(goalsListProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(messageFor(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalsListProvider);
    final repo = ref.watch(goalsRepositoryProvider);
    return PageScaffold(
      title: 'Tujuan personal',
      onBack: () => context.canPop() ? context.pop() : context.go(Routes.home),
      bottom: PillButton(
        label: 'Buat tujuan',
        icon: Icons.add_rounded,
        onPressed: () => context.push(Routes.addGoal),
      ),
      onRefresh: () async => ref.invalidate(goalsListProvider),
      children: [
        AsyncBody<List<Goal>>(
          value: goals,
          onRetry: () => ref.invalidate(goalsListProvider),
          data: (items) => items.isEmpty
              ? EmptyState(
                  icon: Icons.flag_outlined,
                  title: 'Belum ada tujuan',
                  message:
                      'Mulai dari satu kebiasaan kecil yang mudah kamu jaga.',
                  actionLabel: 'Buat tujuan',
                  onAction: () => context.push(Routes.addGoal),
                )
              : Column(
                  children: [
                    for (final g in items) ...[
                      _GoalCard(
                        goal: g,
                        onCheckin: () => _act(
                          context,
                          ref,
                          () => repo.checkin(g.id, {
                            'id': newRecordId(),
                            'eventAt': DateTime.now().toUtc().toIso8601String(),
                            'status': 'completed',
                          }),
                        ),
                        onStatus: (status) => _act(
                          context,
                          ref,
                          () => repo.update(g.id, {
                            'status': status,
                            'expectedVersion': g.version,
                            'reason': 'Diubah pengguna',
                          }),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.onCheckin,
    required this.onStatus,
  });
  final Goal goal;
  final VoidCallback onCheckin;
  final ValueChanged<String> onStatus;

  @override
  Widget build(BuildContext context) {
    final p = goal.progress;
    final paused = goal.status != 'active';
    String num_(num v) =>
        v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(goal.title, style: AppTypography.title)),
              if (paused)
                StatusBadge(
                  label: goal.status == 'completed' ? 'Selesai' : 'Dijeda',
                  tone: InfoTone.neutral,
                ),
            ],
          ),
          Text(
            '${goalTypes[goal.type]} · target ${num_(goal.target)} ${goal.periodLabel}',
            style: AppTypography.secondary,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (p == null || p.value == null)
            Text(
              'Belum ada catatan pada periode ini.',
              style: AppTypography.secondary,
            )
          else ...[
            ClipRRect(
              borderRadius: AppRadius.pillRadius,
              child: LinearProgressIndicator(
                value: ((p.ratio ?? 0).toDouble()).clamp(0, 1),
                minHeight: 8,
                backgroundColor: AppColors.surfaceMuted,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${num_(p.value!)} dari ${num_(p.target)} · ${p.sourceCount} catatan',
              style: AppTypography.caption,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              if (goal.manual && !paused)
                PillButton(
                  label: 'Check-in',
                  icon: Icons.check_rounded,
                  expand: false,
                  onPressed: onCheckin,
                ),
              if (goal.status == 'active')
                TextButton(
                  onPressed: () => onStatus('paused'),
                  child: const Text('Jeda'),
                ),
              if (goal.status == 'paused')
                TextButton(
                  onPressed: () => onStatus('active'),
                  child: const Text('Lanjutkan'),
                ),
              if (goal.status == 'active')
                TextButton(
                  onPressed: () => onStatus('completed'),
                  child: const Text('Tandai selesai'),
                ),
              if (goal.status != 'archived')
                TextButton(
                  onPressed: () =>
                      context.push('/goals/${goal.id}/edit', extra: goal),
                  child: const Text('Ubah'),
                ),
              if (goal.status != 'archived')
                TextButton(
                  onPressed: () => onStatus('archived'),
                  child: const Text('Arsipkan'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
