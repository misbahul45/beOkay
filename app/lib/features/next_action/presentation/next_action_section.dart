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
import '../../../core/widgets/soft_card.dart';
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

String routeForStep(String step, NextAction action) => switch (step) {
  'TODAY' => Routes.log,
  'NEXT_ACTION' => routeForTarget(action.target),
  'CONFIRM' =>
    action.step == 'CONFIRM' ? routeForTarget(action.target) : Routes.coaching,
  'PROGRESS' => Routes.activityWeek,
  'REFLECTION' => Routes.reflection,
  'INSIGHTS' => Routes.insights,
  'CHALLENGES' => Routes.community,
  _ => Routes.log,
};

String formatScore(double v) => v == v.roundToDouble()
    ? v.toStringAsFixed(0)
    : v.toStringAsFixed(1).replaceAll('.', ',');

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
    final extras = !safety && !loggingOnly;
    final lead = [
      NextActionCard(action: a),
      if (extras) ...[
        const SizedBox(height: AppSpacing.sm),
        _FlowChips(flow: view.flow, action: a),
      ],
    ];
    final side = [
      _ProgressCard(view: view, celebrate: celebrate),
      const SizedBox(height: AppSpacing.sm),
      _EnergyCard(current: view.energy),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: LayoutBuilder(
        builder: (context, c) {
          if (extras && c.maxWidth >= 720) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: lead,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: side,
                  ),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...lead,
              if (extras) ...[const SizedBox(height: AppSpacing.sm), ...side],
            ],
          );
        },
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
      child: SoftCard(
        color: color,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BeOkaySpark(size: 48, state: sparkStateFromWire(action.spark)),
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
                        const SizedBox(height: AppSpacing.xxs),
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
            const SizedBox(height: AppSpacing.md),
            PillButton(
              label: _buttons[action.kind] ?? 'Buka',
              kind: safety || celebrate
                  ? PillButtonKind.secondary
                  : PillButtonKind.ink,
              onPressed: () => context.push(routeForTarget(action.target)),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlowChips extends StatelessWidget {
  const _FlowChips({required this.flow, required this.action});

  final List<String> flow;
  final NextAction action;

  @override
  Widget build(BuildContext context) {
    final steps = flow.take(5).toList();
    final current = action.step;
    return Semantics(
      container: true,
      label: 'Alur hari ini, sekarang: ${_stepLabels[current] ?? current}',
      child: Wrap(
        spacing: AppSpacing.xs,
        children: [
          for (final s in steps)
            PillChip(
              label: _stepLabels[s] ?? s,
              selected: s == current,
              onTap: () => context.push(routeForStep(s, action)),
            ),
        ],
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
    final score = formatScore(w.total);
    return Semantics(
      container: true,
      label:
          'Progres minggu ini: ${w.activeDays} hari aktif, ${w.deviceDays} dari perangkat, skor minggu ini $score, rekor 7 hari ${view.best7}.',
      child: ExcludeSemantics(
        child: SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PROGRES MINGGU INI', style: AppTypography.overline),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  stat('${w.activeDays}', 'hari aktif'),
                  stat('${w.deviceDays}', 'dari perangkat'),
                  stat(score, 'skor minggu ini'),
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
                'Rekor 7 hari: ${view.best7}. Hari tanpa catatan bukan kegagalan; skor hanya bertambah.',
                style: AppTypography.caption,
              ),
            ],
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
  bool _saved = false;

  Future<void> _set(String v) async {
    if (_saving || v == _value) return;
    final before = _value;
    setState(() {
      _value = v;
      _saving = true;
      _saved = false;
    });
    try {
      await ref.read(nextActionRepositoryProvider).setEnergy(v);
      if (mounted) setState(() => _saved = true);
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
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Overline('BAGAIMANA TENAGAMU HARI INI?'),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final (wire, label) in options)
                PillChip(
                  label: label,
                  selected: _value == wire,
                  onTap: _saving ? null : () => _set(wire),
                ),
              if (_saving)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            liveRegion: true,
            child: Text(
              _saved
                  ? 'Tersimpan. Saat kamu lelah, pengingat ditahan hari ini.'
                  : 'Opsional. Saat kamu lelah, pengingat ditahan hari ini.',
              style: AppTypography.caption,
            ),
          ),
        ],
      ),
    );
  }
}
