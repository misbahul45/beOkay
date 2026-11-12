import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/usage_tracker.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/detail_kit.dart';
import '../application/nutrition_controller.dart';

class MealContextSection extends ConsumerStatefulWidget {
  const MealContextSection({super.key, required this.id});
  final String id;
  @override
  ConsumerState<MealContextSection> createState() => _MealContextSectionState();
}

class _MealContextSectionState extends ConsumerState<MealContextSection> {
  bool tracked = false;

  @override
  Widget build(BuildContext context) {
    final ctx = ref.watch(mealContextProvider(widget.id)).value;
    if (ctx == null) return const SizedBox.shrink();
    final paired = ctx.before != null || ctx.after != null;
    if (!tracked && (paired || ctx.carbCompared)) {
      tracked = true;
      ref
          .read(usageTrackerProvider)
          .track('context_viewed', domain: 'meal', meta: {'shown': paired});
    }
    return Column(
      children: [
        DetailSection(
          title: 'Dibandingkan catatanmu',
          children: [Text(ctx.carbLine, style: AppTypography.body)],
        ),
        DetailSection(
          title: 'Glukosa di sekitar makan ini',
          children: [
            if (!paired)
              Text(ctx.pairHint ?? '', style: AppTypography.secondary),
            if (ctx.before != null)
              DetailRow(
                'Sebelum',
                '${ctx.before!.value} ${ctx.unit} · ${ctx.before!.offset}',
              ),
            if (ctx.after != null)
              DetailRow(
                'Sesudah',
                '${ctx.after!.value} ${ctx.unit} · ${ctx.after!.offset}',
              ),
            if (ctx.difference != null)
              DetailRow(
                'Selisih',
                '${ctx.difference! > 0 ? '+' : ''}${ctx.difference} ${ctx.unit}',
              ),
            if (paired) ...[
              const SizedBox(height: 4),
              Text(ctx.pairNote, style: AppTypography.caption),
            ],
          ],
        ),
      ],
    );
  }
}
