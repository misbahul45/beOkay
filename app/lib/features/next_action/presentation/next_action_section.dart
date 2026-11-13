import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/beokay_spark.dart';
import '../../../core/widgets/choice_chips.dart';
import '../../../core/widgets/pill_button.dart';
import '../application/next_action_controller.dart';
import '../data/next_action_repository.dart';

const _stepLabels = {
  'TODAY': 'Hari ini',
  'NEXT_ACTION': 'Berikutnya',
  'CONFIRM': 'Konfirmasi',
  'PROGRESS': 'Progres',
  'REFLECTION': 'Refleksi',
  'INSIGHTS': 'Wawasan',
  'CHALLENGES': 'Tantangan',
};

const _kickers = {
  'SAFETY_FOLLOW_UP': 'UTAMAKAN KESELAMATAN',
  'CONFIRM_RECOMMENDATION': 'LANGKAH BERIKUTNYA · KONFIRMASI',
  'CONFIRM_PLAN': 'LANGKAH BERIKUTNYA · KONFIRMASI',
  'CONFIRM_MEMORY': 'LANGKAH BERIKUTNYA · KONFIRMASI',
  'DO_PLANNED_ACTION': 'LANGKAH BERIKUTNYA',
  'CELEBRATE_RETURN': 'PROGRES',
  'WEEKLY_REFLECTION': 'REFLEKSI',
  'LOG_SOMETHING': 'CATAT HARIMU',
};

const _buttons = {
  'SAFETY_FOLLOW_UP': 'Buka percakapan',
  'CONFIRM_RECOMMENDATION': 'Lihat pilihan',
  'CONFIRM_PLAN': 'Lihat rencana',
  'CONFIRM_MEMORY': 'Tinjau ingatan',
  'DO_PLANNED_ACTION': 'Buka rencana',
  'CELEBRATE_RETURN': 'Lihat progres',
  'WEEKLY_REFLECTION': 'Mulai refleksi',
  'LOG_SOMETHING': 'Catat',
};

String routeForTarget(String target) => switch (target) {
  'COACH' => Routes.coach,
  'COACHING' => Routes.coaching,
  'MEMORY' => Routes.memory,
  'REFLECTION' => Routes.reflection,
  'INSIGHTS' => Routes.insights,
  _ => Routes.log,
};

class NextActionSection extends ConsumerWidget {
  const NextActionSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(nextActionProvider).value;
    if (view == null) return const SizedBox.shrink();
    final a = view.action;
    final safety = a.kind == 'SAFETY_FOLLOW_UP';
    final celebrate = a.kind == 'CELEBRATE_RETURN';
    final loggingOnly = view.journey == 'UNDETERMINED';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NextActionCard(action: a),
          if (!safety && !loggingOnly) ...[
            const SizedBox(height: AppSpacing.sm),
            _FlowChips(flow: view.flow, current: a.step),
            const SizedBox(height: AppSpacing.sm),
            _ProgressCard(view: view, celebrate: celebrate),
            const SizedBox(height: AppSpacing.sm),
            _EnergyCard(current: view.energy),
          ],
        ],
      ),
    );
  }
}

class NextActionCard extends StatelessWidget {
  const NextActionCard({super.key, required this.action});

  final NextAction action;

  @override
  Widget build(BuildContext context) {
    final safety = action.kind == 'SAFETY_FOLLOW_UP';
    final celebrate = action.kind == 'CELEBRATE_RETURN';
    final color = safety
        ? AppColors.surfaceMuted
        : celebrate
        ? AppColors.cream
        : AppColors.surface;
    final kicker = _kickers[action.kind] ?? 'LANGKAH BERIKUTNYA';
    return Semantics(
      container: true,
      label: '$kicker. ${action.title}. ${action.body}',
      child: Material(
        color: color,
        borderRadius: AppRadius.cardRadius,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  BeOkaySpark(
                    size: 48,
                    state: sparkStateFromWire(action.spark),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            kicker,
                            style: AppTypography.overline.copyWith(
                              color: safety
                                  ? AppColors.textSecondary
                                  : celebrate
                                  ? AppColors.sparkAmber
                                  : AppColors.brand,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(action.title, style: AppTypography.title),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (action.body.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                ExcludeSemantics(
                  child: Text(action.body, style: AppTypography.secondary),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              PillButton(
                label: _buttons[action.kind] ?? 'Buka',
                kind: safety || celebrate
                    ? PillButtonKind.secondary
                    : PillButtonKind.primary,
                onPressed: () => context.push(routeForTarget(action.target)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlowChips extends StatelessWidget {
  const _FlowChips({required this.flow, required this.current});

  final List<String> flow;
  final String current;

  @override
  Widget build(BuildContext context) {
    final steps = flow.take(5).toList();
    return Semantics(
      label: 'Alur hari ini, sekarang: ${_stepLabels[current] ?? current}',
      child: ExcludeSemantics(
        child: Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final s in steps)
              PillChip(
                label: _stepLabels[s] ?? s,
                selected: s == current,
                onTap: null,
              ),
          ],
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.view, required this.celebrate});

  final NextActionView view;
  final bool celebrate;

  @override
  Widget build(BuildContext context) {
    final w = view.week;
    Widget stat(String value, String label) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AppTypography.metric),
          Text(label, style: AppTypography.caption),
        ],
      ),
    );
    return Semantics(
      container: true,
      label:
          'Progres minggu ini: ${w.activeDays} hari aktif, ${w.deviceDays} dari perangkat, rekor 7 hari ${view.best7}.',
      child: ExcludeSemantics(
        child: Material(
          color: AppColors.surface,
          borderRadius: AppRadius.cardRadius,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PROGRES MINGGU INI', style: AppTypography.overline),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    stat('${w.activeDays}', 'hari aktif'),
                    stat('${w.deviceDays}', 'dari perangkat'),
                    stat('${view.best7}', 'rekor 7 hari'),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (w.activeDays / 7).clamp(0, 1),
                    minHeight: 8,
                    color: AppColors.brand,
                    backgroundColor: AppColors.border,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Hari tanpa catatan bukan kegagalan; skor hanya bertambah.',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EnergyCard extends ConsumerStatefulWidget {
  const _EnergyCard({required this.current});

  final String? current;

  @override
  ConsumerState<_EnergyCard> createState() => _EnergyCardState();
}

class _EnergyCardState extends ConsumerState<_EnergyCard> {
  late String? _value = widget.current;
  bool _saving = false;

  Future<void> _set(String v) async {
    if (_saving || v == _value) return;
    final before = _value;
    setState(() {
      _value = v;
      _saving = true;
    });
    try {
      await ref.read(nextActionRepositoryProvider).setEnergy(v);
    } catch (_) {
      if (!mounted) return;
      setState(() => _value = before);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum bisa disimpan. Coba lagi.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const options = [('LOW', 'Lelah'), ('OK', 'Biasa'), ('HIGH', 'Segar')];
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadius.cardRadius,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'BAGAIMANA TENAGAMU HARI INI?',
                style: AppTypography.overline,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final (wire, label) in options)
                  PillChip(
                    label: label,
                    selected: _value == wire,
                    onTap: () => _set(wire),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Opsional. Saat kamu lelah, pengingat ditahan hari ini.',
              style: AppTypography.caption,
            ),
          ],
        ),
      ),
    );
  }
}
