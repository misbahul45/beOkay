import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/domain_style.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/pill_button.dart';
import '../data/conversation_models.dart';

typedef DecideCallback =
    Future<void> Function(ChatRecommendation r, {required bool accept});

String _num(num v) {
  final rounded = v is int || v == v.roundToDouble()
      ? v.round().toString()
      : v.toStringAsFixed(1);
  return rounded.replaceAll('.', ',');
}

DomainStyle _domain(String key) => switch (key) {
  'activity' => DomainStyle.activity,
  'glucose' => DomainStyle.glucose,
  'nutrition' => DomainStyle.meal,
  'medication' => DomainStyle.medication,
  _ => DomainStyle.goal,
};

class UserBubble extends StatelessWidget {
  const UserBubble({super.key, required this.text, this.faded = false});
  final String text;
  final bool faded;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.8,
      ),
      child: Opacity(
        opacity: faded ? 0.6 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Text(
            text,
            style: AppTypography.body.copyWith(color: AppColors.onPrimary),
          ),
        ),
      ),
    ),
  );
}

class AssistantBubble extends StatelessWidget {
  const AssistantBubble({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.88,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(6),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: Text(text, style: AppTypography.body),
      ),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.color, this.radius = 18});
  final Widget child;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.cardPadding),
    decoration: BoxDecoration(
      color: color ?? AppColors.surface,
      borderRadius: BorderRadius.circular(radius),
      border: color == null ? Border.all(color: AppColors.border) : null,
    ),
    child: child,
  );
}

class _IconCircle extends StatelessWidget {
  const _IconCircle({required this.style});
  final DomainStyle style;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(color: style.tint, shape: BoxShape.circle),
    child: Icon(style.icon, size: 19, color: style.ink),
  );
}

class StatisticCard extends StatelessWidget {
  const StatisticCard({super.key, required this.part});
  final StatisticPart part;

  @override
  Widget build(BuildContext context) {
    final style = _domain(part.domain);
    final value = part.value == null ? '–' : _num(part.value!);
    return Semantics(
      container: true,
      label: '${part.label}: $value ${part.unit ?? ''}. ${part.caption}',
      excludeSemantics: true,
      child: _Card(
        child: Row(
          children: [
            _IconCircle(style: style),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(part.label, style: AppTypography.secondaryStrong),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: value, style: AppTypography.metric),
                        if (part.unit != null)
                          TextSpan(
                            text: ' ${part.unit}',
                            style: AppTypography.secondary,
                          ),
                      ],
                    ),
                  ),
                  if (part.caption.isNotEmpty)
                    Text(part.caption, style: AppTypography.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RecommendationGroup extends StatefulWidget {
  const RecommendationGroup({
    super.key,
    required this.part,
    required this.busy,
    required this.onDecide,
  });
  final RecommendationsPart part;
  final Set<String> busy;
  final DecideCallback onDecide;

  @override
  State<RecommendationGroup> createState() => _RecommendationGroupState();
}

class _RecommendationGroupState extends State<RecommendationGroup> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final part = widget.part;
    if (part.hidden) {
      return const InfoCard(
        tone: InfoTone.warning,
        text: 'Persetujuan dicabut, jadi saran ini tidak dapat dilanjutkan.',
      );
    }
    if (part.items.isEmpty) return const SizedBox.shrink();
    final first = part.items.first;
    final others = part.items.skip(1).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResultCard(
          item: first,
          primary: true,
          busy: widget.busy.contains(first.id),
          onDecide: widget.onDecide,
        ),
        if (others.isNotEmpty) ...[
          if (expanded)
            for (final o in others) ...[
              const SizedBox(height: AppSpacing.xs),
              ResultCard(
                item: o,
                primary: false,
                busy: widget.busy.contains(o.id),
                onDecide: widget.onDecide,
              ),
            ],
          TextButton.icon(
            onPressed: () => setState(() => expanded = !expanded),
            iconAlignment: IconAlignment.end,
            icon: Icon(
              expanded
                  ? Icons.expand_less_rounded
                  : Icons.chevron_right_rounded,
              size: 20,
            ),
            label: Text(
              expanded
                  ? 'Sembunyikan pilihan lain'
                  : 'Lihat ${others.length} pilihan lain',
            ),
          ),
        ],
      ],
    );
  }
}

String _subtitle(ChatRecommendation r, bool primary) {
  if (r.isActivity) return '${r.activityMinutes ?? '–'} menit · dari riwayatmu';
  return switch (r.match) {
    'EXACT' when primary => 'Paling sesuai dengan pencarianmu',
    'EXACT' => 'Sesuai dengan pencarianmu',
    'CLOSE' => 'Mirip dengan pencarianmu',
    _ => r.provenance,
  };
}

class ResultCard extends StatelessWidget {
  const ResultCard({
    super.key,
    required this.item,
    required this.primary,
    required this.busy,
    required this.onDecide,
  });
  final ChatRecommendation item;
  final bool primary, busy;
  final DecideCallback onDecide;

  @override
  Widget build(BuildContext context) {
    final style = item.isActivity ? DomainStyle.activity : DomainStyle.meal;
    final name = item.isActivity ? item.activityLabel : item.name;
    return _Card(
      radius: AppRadius.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconCircle(style: style),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: primary
                          ? AppTypography.title
                          : AppTypography.bodyStrong,
                    ),
                    Text(
                      _subtitle(item, primary),
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!item.isActivity) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              item.calories == null
                  ? 'Energi belum diketahui'
                  : 'Energi ${_num(item.calories!)} kkal per 100 g',
              style: AppTypography.secondaryStrong,
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (item.offered)
                CardAction(
                  label: 'Tambahkan ke rencana',
                  primary: true,
                  loading: busy,
                  onPressed: busy ? null : () => onDecide(item, accept: true),
                )
              else
                StatusBadge(
                  label: item.statusLabel,
                  tone: item.status == 'ACCEPTED'
                      ? InfoTone.info
                      : InfoTone.neutral,
                ),
              CardAction(
                label: 'Lihat detail',
                onPressed: () => showRecommendationDetail(
                  context,
                  item: item,
                  busy: busy,
                  onDecide: onDecide,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const _nutrients = [
  ('calories', 'Energi', 'kkal'),
  ('carbohydrates', 'Karbohidrat', 'g'),
  ('protein', 'Protein', 'g'),
  ('fat', 'Lemak', 'g'),
  ('fiber', 'Serat', 'g'),
];

Future<void> showRecommendationDetail(
  BuildContext context, {
  required ChatRecommendation item,
  required bool busy,
  required DecideCallback onDecide,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return _showDetail(context, item: item, busy: busy, onDecide: onDecide);
}

Future<void> _showDetail(
  BuildContext context, {
  required ChatRecommendation item,
  required bool busy,
  required DecideCallback onDecide,
}) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: AppColors.surface,
  builder: (sheet) {
    Future<void> act(bool accept) async {
      Navigator.of(sheet).pop();
      await onDecide(item, accept: accept);
    }

    final coverage = switch (item.completeness) {
      'COMPLETE' => 'data lengkap',
      'PARTIAL' => 'data sebagian',
      _ => 'data belum ada',
    };
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheet).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  item.isActivity ? item.activityLabel : item.name,
                  style: AppTypography.heading,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.isActivity
                    ? 'Dari riwayat aktivitasmu'
                    : 'Nilai per 100 g · $coverage',
                style: AppTypography.caption,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (item.isActivity)
                _Row('Durasi', '${item.activityMinutes ?? '–'} menit')
              else
                for (final (key, label, unit) in _nutrients)
                  _Row(
                    label,
                    item.per100g[key] == null
                        ? null
                        : '${_num(item.per100g[key]!)} $unit',
                  ),
              const SizedBox(height: AppSpacing.sm),
              Text('Sumber: ${item.provenance}', style: AppTypography.caption),
              if (item.explanation.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(item.explanation, style: AppTypography.secondary),
                if (item.writtenByModel)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Ditulis dengan bantuan AI.',
                      style: AppTypography.caption,
                    ),
                  ),
              ],
              if (item.limitations.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _Card(
                  color: AppColors.surfaceMuted,
                  radius: AppRadius.md,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final l in item.limitations)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('• $l', style: AppTypography.caption),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (item.offered)
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    PillButton(
                      label: 'Tambahkan ke rencana',
                      expand: false,
                      onPressed: busy ? null : () => act(true),
                    ),
                    PillButton(
                      label: 'Lewati',
                      kind: PillButtonKind.secondary,
                      expand: false,
                      onPressed: busy ? null : () => act(false),
                    ),
                  ],
                )
              else
                StatusBadge(
                  label: item.statusLabel,
                  tone: item.status == 'ACCEPTED'
                      ? InfoTone.info
                      : InfoTone.neutral,
                ),
            ],
          ),
        ),
      ),
    );
  },
);

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: AppTypography.body)),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            value ?? 'tidak diketahui',
            textAlign: TextAlign.end,
            style: value == null
                ? AppTypography.secondary
                : AppTypography.bodyStrong,
          ),
        ),
      ],
    ),
  );
}

class NoMatchCard extends StatelessWidget {
  const NoMatchCard({super.key, required this.part, required this.onEdit});
  final NoMatchPart part;
  final ValueChanged<String> onEdit;

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Makanan belum ditemukan', style: AppTypography.title),
        const SizedBox(height: 4),
        Text(part.text, style: AppTypography.secondary),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            ChatChip(label: 'Ubah pencarian', onTap: () => onEdit(part.query)),
            ChatChip(
              label: 'Catat manual',
              onTap: () => context.push(Routes.addMeal),
            ),
          ],
        ),
      ],
    ),
  );
}

class SafetyCard extends StatelessWidget {
  const SafetyCard({super.key, required this.part});
  final SafetyPart part;

  @override
  Widget build(BuildContext context) {
    final bg = part.urgent
        ? AppColors.errorBackground
        : AppColors.warningBackground;
    final fg = part.urgent
        ? AppColors.errorForeground
        : AppColors.warningForeground;
    return Semantics(
      container: true,
      liveRegion: true,
      child: _Card(
        color: bg,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              part.urgent
                  ? Icons.emergency_outlined
                  : Icons.health_and_safety_outlined,
              color: fg,
              size: 22,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    part.title,
                    style: AppTypography.bodyStrong.copyWith(color: fg),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    part.text,
                    style: AppTypography.secondary.copyWith(color: fg),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatChip extends StatelessWidget {
  const ChatChip({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    shape: StadiumBorder(side: BorderSide(color: AppColors.border)),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: AppTypography.secondaryStrong.copyWith(
                    color: AppColors.brand,
                  ),
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 4),
                Icon(icon, size: 16, color: AppColors.brand),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class CardAction extends StatelessWidget {
  const CardAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.loading = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool primary, loading;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(
        Size(0, AppSpacing.minTouchTarget),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16),
      ),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      textStyle: WidgetStatePropertyAll(AppTypography.secondaryStrong),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final child = loading
        ? SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.onPrimary,
            ),
          )
        : Text(label);
    return primary
        ? FilledButton(
            onPressed: onPressed,
            style: style.copyWith(
              backgroundColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.disabled)
                    ? AppColors.disabled
                    : AppColors.primary,
              ),
              foregroundColor: WidgetStatePropertyAll(AppColors.onPrimary),
            ),
            child: child,
          )
        : FilledButton(
            onPressed: onPressed,
            style: style.copyWith(
              backgroundColor: WidgetStatePropertyAll(AppColors.surfaceMuted),
              foregroundColor: WidgetStatePropertyAll(AppColors.brand),
            ),
            child: child,
          );
  }
}
