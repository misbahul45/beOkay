import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/error_messages.dart';

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

const mealCategoryLabels = {
  'breakfast': 'Sarapan',
  'lunch': 'Makan siang',
  'dinner': 'Makan malam',
  'snack': 'Camilan',
};

String _unitName(String unit) => switch (unit) {
  'portion' => 'porsi',
  'piece' => 'buah',
  'g' => 'g',
  'ml' => 'ml',
  _ => unit,
};

String quantityLabel(DraftItem i) =>
    '${_num(i.quantity)} ${i.unitLabel ?? _unitName(i.unit)}';

String _gramsLine(DraftItem i) {
  if (i.grams == null) return 'Berat belum diisi';
  final g = '${_num(i.grams!)} g';
  return i.gramsBasis == 'user_estimate' ? '$g (dari takaranmu)' : g;
}

class MealDraftCard extends StatelessWidget {
  const MealDraftCard({
    super.key,
    required this.draft,
    required this.busy,
    required this.onReview,
    required this.onDiscard,
    required this.onOpenMeal,
    required this.onWebSearch,
  });
  final MealDraft draft;
  final bool busy;
  final VoidCallback onReview, onDiscard, onOpenMeal;
  final ValueChanged<DraftItem> onWebSearch;

  @override
  Widget build(BuildContext context) {
    final d = draft;
    final style = DomainStyle.meal;
    final category = mealCategoryLabels[d.category] ?? 'Makan';
    final local = d.consumedAt.toLocal();
    final now = DateTime.now();
    final today =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final when =
        '${today ? 'Hari ini' : '${local.day}/${local.month}'} · ${d.localTime.replaceAll(':', '.')}';
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
                      d.open ? 'Draf ${category.toLowerCase()}' : category,
                      style: AppTypography.title,
                    ),
                    Text(
                      '$when · ${d.items.length} makanan',
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final i in d.items.take(6))
            _DraftRow(
              item: i,
              open: d.open,
              busy: busy,
              onWebSearch: () => onWebSearch(i),
            ),
          const SizedBox(height: AppSpacing.xs),
          if (d.open)
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                CardAction(
                  label: 'Periksa & simpan',
                  primary: true,
                  loading: busy,
                  onPressed: busy ? null : onReview,
                ),
                CardAction(label: 'Buang', onPressed: busy ? null : onDiscard),
              ],
            )
          else
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusBadge(
                  label: switch (d.status) {
                    'SAVED' => 'Tersimpan di catatan makan',
                    'DISCARDED' => 'Dibuang',
                    _ => 'Kedaluwarsa',
                  },
                  tone: d.status == 'SAVED' ? InfoTone.info : InfoTone.neutral,
                ),
                if (d.status == 'SAVED' && d.mealId != null)
                  CardAction(label: 'Lihat catatan', onPressed: onOpenMeal),
              ],
            ),
        ],
      ),
    );
  }
}

String _capitalized(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

class _DraftRow extends StatelessWidget {
  const _DraftRow({
    required this.item,
    required this.open,
    required this.busy,
    required this.onWebSearch,
  });
  final DraftItem item;
  final bool open, busy;
  final VoidCallback onWebSearch;

  @override
  Widget build(BuildContext context) {
    final c = item.selectedCandidate;
    final ok = c != null;
    final detail = ok
        ? '${quantityLabel(item)} · ${c.name} (${c.sourceLabel})'
        : quantityLabel(item);
    final status = ok
        ? _gramsLine(item)
        : switch (item.webSearchStatus) {
            'FOUND' =>
              'Ada ${item.webCount} hasil web, pilih di Periksa & simpan',
            'NONE' => 'Tidak ditemukan di web, dicatat tanpa gizi',
            'UNAVAILABLE' => 'Pencarian web gagal, dicatat tanpa gizi',
            _ => 'Belum ditemukan, dicatat tanpa gizi',
          };
    final canSearchWeb =
        open &&
        !item.hasLocalMatch &&
        (item.webSearchStatus == null || item.webSearchStatus == 'UNAVAILABLE');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 22,
            width: 22,
            decoration: BoxDecoration(
              color: ok ? AppColors.brandTint : AppColors.warningBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(
              ok ? Icons.check_rounded : Icons.priority_high_rounded,
              size: 14,
              color: ok ? AppColors.brand : AppColors.warningForeground,
            ),
          ),
          const SizedBox(width: AppSpacing.xs + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_capitalized(item.name), style: AppTypography.bodyStrong),
                Text(detail, style: AppTypography.caption),
                if (open || !ok)
                  Text(
                    item.photoConfidence == 'low'
                        ? '$status · dugaan foto kurang yakin'
                        : status,
                    style: AppTypography.caption.copyWith(
                      color: ok ? AppColors.brand : AppColors.warningForeground,
                    ),
                  ),
                if (canSearchWeb)
                  TextButton.icon(
                    onPressed: busy ? null : onWebSearch,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.transparent,
                      minimumSize: const Size(0, AppSpacing.minTouchTarget),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.travel_explore_rounded, size: 18),
                    label: const Text('Cari di web'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

typedef DraftSave =
    Future<void> Function({
      required String category,
      required DateTime consumedAt,
      required List<Map<String, dynamic>> items,
    });

Future<void> showMealDraftEditor(
  BuildContext context, {
  required MealDraft draft,
  required DraftSave onSave,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (_) => _DraftEditor(draft: draft, onSave: onSave),
  );
}

class _EditorItem {
  _EditorItem(this.source)
    : candidateKey = source.selected,
      quantity = TextEditingController(text: _num(source.quantity)),
      grams = TextEditingController(
        text: source.unit == 'g' || source.grams == null
            ? ''
            : _num(source.grams!),
      );
  final DraftItem source;
  bool include = true;
  String? candidateKey;
  final TextEditingController quantity, grams;
}

double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

class _DraftEditor extends StatefulWidget {
  const _DraftEditor({required this.draft, required this.onSave});
  final MealDraft draft;
  final DraftSave onSave;

  @override
  State<_DraftEditor> createState() => _DraftEditorState();
}

class _DraftEditorState extends State<_DraftEditor> {
  late String category = widget.draft.category;
  late DateTime consumedAt = widget.draft.consumedAt.toLocal();
  late final items = [for (final i in widget.draft.items) _EditorItem(i)];
  bool saving = false;
  String? error;

  @override
  void dispose() {
    for (final i in items) {
      i.quantity.dispose();
      i.grams.dispose();
    }
    super.dispose();
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(consumedAt),
    );
    if (t == null) return;
    final next = DateTime(
      consumedAt.year,
      consumedAt.month,
      consumedAt.day,
      t.hour,
      t.minute,
    );
    setState(
      () => consumedAt = next.isAfter(DateTime.now()) ? DateTime.now() : next,
    );
  }

  Future<void> _save() async {
    final chosen = items.where((i) => i.include).toList();
    if (chosen.isEmpty) {
      setState(() => error = 'Sisakan paling sedikit satu makanan.');
      return;
    }
    final payload = <Map<String, dynamic>>[];
    for (final i in chosen) {
      final q = _parse(i.quantity.text);
      final g = i.grams.text.trim().isEmpty ? null : _parse(i.grams.text);
      if (q == null ||
          q <= 0 ||
          (i.grams.text.trim().isNotEmpty && (g == null || g <= 0))) {
        setState(() => error = 'Periksa jumlah dan berat ${i.source.name}.');
        return;
      }
      payload.add({
        'index': i.source.index,
        'candidateKey': i.candidateKey,
        'name': i.source.name,
        'quantity': q,
        'unit': i.source.unit,
        'grams': i.source.unit == 'g' ? null : g,
      });
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSave(
        category: category,
        consumedAt: consumedAt,
        items: payload,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = messageFor(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: [
          Semantics(
            header: true,
            child: Text('Periksa catatan makan', style: AppTypography.heading),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final e in mealCategoryLabels.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: category == e.key,
                  onSelected: saving
                      ? null
                      : (_) => setState(() => category = e.key),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton.icon(
            onPressed: saving ? null : _pickTime,
            icon: const Icon(Icons.schedule_rounded),
            label: Text(
              'Waktu ${TimeOfDay.fromDateTime(consumedAt).format(context)}',
            ),
          ),
          for (final i in items) ...[
            const SizedBox(height: AppSpacing.sm),
            _ItemEditor(
              item: i,
              enabled: !saving,
              onChanged: () => setState(() {}),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          const InfoCard(
            tone: InfoTone.warning,
            text:
                'Tanpa berat, gizi makanan itu tidak dihitung. Tidak ada angka yang ditebak.',
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ErrorBanner(error!),
          ],
          const SizedBox(height: AppSpacing.md),
          PillButton(
            label: 'Simpan ke catatan makan',
            loading: saving,
            onPressed: saving ? null : _save,
          ),
        ],
      ),
    ),
  );
}

class _ItemEditor extends StatelessWidget {
  const _ItemEditor({
    required this.item,
    required this.enabled,
    required this.onChanged,
  });
  final _EditorItem item;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final s = item.source;
    final selected = s.candidates
        .where((c) => c.key == item.candidateKey)
        .firstOrNull;
    return Opacity(
      opacity: item.include ? 1 : 0.5,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(s.name, style: AppTypography.title)),
                IconButton(
                  tooltip: item.include
                      ? 'Keluarkan ${s.name}'
                      : 'Masukkan lagi ${s.name}',
                  onPressed: enabled
                      ? () {
                          item.include = !item.include;
                          onChanged();
                        }
                      : null,
                  icon: Icon(
                    item.include
                        ? Icons.remove_circle_outline_rounded
                        : Icons.add_circle_outline_rounded,
                  ),
                ),
              ],
            ),
            if (s.photoConfidence != null)
              Text(
                'Dugaan dari foto (${switch (s.photoConfidence) {
                  'high' => 'cukup yakin',
                  'medium' => 'agak yakin',
                  _ => 'kurang yakin',
                }}). Pastikan namanya benar.',
                style: AppTypography.caption,
              ),
            const SizedBox(height: AppSpacing.xs),
            DropdownButtonFormField<String?>(
              initialValue: item.candidateKey,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Makanan'),
              items: [
                for (final c in s.candidates)
                  DropdownMenuItem(
                    value: c.key,
                    child: Text(
                      '${c.name} · ${c.sourceLabel}${c.per100g['calories'] == null ? '' : ' · ${_num(c.per100g['calories']!)} kkal/100 g'}${c.excluded ? ' · cocok dengan alergimu' : ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const DropdownMenuItem(
                  value: null,
                  child: Text('Tanpa referensi (gizi tidak dihitung)'),
                ),
              ],
              onChanged: enabled && item.include
                  ? (v) {
                      item.candidateKey = v;
                      onChanged();
                    }
                  : null,
            ),
            if (selected?.fromWeb ?? false)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Angka dari ${selected!.host ?? 'situs web'}, belum diverifikasi beOkay. Periksa sebelum menyimpan.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.warningForeground,
                  ),
                ),
              ),
            if (selected?.excluded ?? false)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Nama ini cocok dengan alergi atau pembatasanmu.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.warningForeground,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: item.quantity,
                    enabled: enabled && item.include,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Jumlah',
                      suffixText: s.unitLabel ?? _unitName(s.unit),
                    ),
                  ),
                ),
                if (s.unit != 'g') ...[
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: TextField(
                      controller: item.grams,
                      enabled: enabled && item.include,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Berat (opsional)',
                        suffixText: 'g',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MemoryProposalCard extends StatelessWidget {
  const MemoryProposalCard({
    super.key,
    required this.proposal,
    required this.busy,
    required this.onAnswer,
  });
  final MemoryProposal proposal;
  final bool busy;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    final p = proposal;
    if (p.status == 'DISMISSED') return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            p.status == 'ACTIVE'
                ? 'Diingat untuk saran berikutnya'
                : 'Ingat ini untuk saran berikutnya?',
            style: AppTypography.secondaryStrong.copyWith(
              color: AppColors.goalInk,
            ),
          ),
          const SizedBox(height: 2),
          Text(p.content, style: AppTypography.title),
          if (p.status == 'PROPOSED') ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                CardAction(
                  label: 'Ingat',
                  primary: true,
                  loading: busy,
                  onPressed: busy ? null : () => onAnswer(true),
                ),
                CardAction(
                  label: 'Jangan',
                  onPressed: busy ? null : () => onAnswer(false),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class PhotoBubble extends StatelessWidget {
  const PhotoBubble({super.key, required this.items, this.faded = false});
  final List<({String name, String confidence})> items;
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
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.photo_camera_outlined,
                    size: 18,
                    color: AppColors.onPrimary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Foto makanan',
                    style: AppTypography.bodyStrong.copyWith(
                      color: AppColors.onPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                items.map((i) => i.name).join(', '),
                style: AppTypography.secondary.copyWith(
                  color: AppColors.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class BasisLink extends StatelessWidget {
  const BasisLink({super.key, required this.basis, required this.onManage});
  final Basis basis;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () => showBasisSheet(context, basis: basis, onManage: onManage),
    style: TextButton.styleFrom(
      padding: EdgeInsets.zero,
      backgroundColor: Colors.transparent,
      foregroundColor: AppColors.textSecondary,
      minimumSize: const Size(0, AppSpacing.minTouchTarget),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    icon: const Icon(Icons.info_outline_rounded, size: 16),
    label: Text(
      basis.memories.isEmpty
          ? 'Dasar jawaban'
          : 'Dasar jawaban · memakai ingatan',
    ),
  );
}

Future<void> showBasisSheet(
  BuildContext context, {
  required Basis basis,
  required VoidCallback onManage,
}) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: AppColors.surface,
  builder: (sheet) => SafeArea(
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
            child: Text('Dasar jawaban ini', style: AppTypography.heading),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final s in basis.sources) _Row('Sumber', s),
          for (final m in basis.memories) _Row('Ingatan', m),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Tidak ada data lain yang dipakai.',
            style: AppTypography.caption,
          ),
          if (basis.memories.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            PillButton(
              label: 'Kelola ingatan',
              kind: PillButtonKind.secondary,
              expand: false,
              onPressed: () {
                Navigator.of(sheet).pop();
                onManage();
              },
            ),
          ],
        ],
      ),
    ),
  ),
);

class ReflectionCard extends StatelessWidget {
  const ReflectionCard({super.key, required this.part});

  final ReflectionPart part;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final p in part.positives)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_rounded, size: 18, color: AppColors.brand),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: Text(p, style: AppTypography.body)),
                ],
              ),
            ),
          if (part.positives.isNotEmpty) const SizedBox(height: AppSpacing.xs),
          PillButton(
            label: part.done
                ? 'Lihat refleksi mingguan'
                : 'Buka refleksi mingguan',
            kind: part.done ? PillButtonKind.secondary : PillButtonKind.primary,
            expand: false,
            onPressed: () => context.push(Routes.reflection),
          ),
        ],
      ),
    );
  }
}
