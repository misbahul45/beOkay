import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/usage_tracker.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/detail_kit.dart';
import '../application/glucose_controller.dart';

class GlucoseContextSection extends ConsumerStatefulWidget {
  const GlucoseContextSection({super.key, required this.id});
  final String id;
  @override
  ConsumerState<GlucoseContextSection> createState() =>
      _GlucoseContextSectionState();
}

class _GlucoseContextSectionState extends ConsumerState<GlucoseContextSection> {
  bool tracked = false;

  @override
  Widget build(BuildContext context) {
    final ctx = ref.watch(glucoseContextProvider(widget.id)).value;
    if (ctx == null) return const SizedBox.shrink();
    if (!tracked && ctx.comparison != null) {
      tracked = true;
      ref
          .read(usageTrackerProvider)
          .track('context_viewed', domain: 'glucose', meta: {'shown': true});
    }
    return DetailSection(
      title: 'Dibandingkan catatanmu',
      children: [
        Text(ctx.line, style: AppTypography.body),
        if (ctx.previousValue != null)
          DetailRow(
            'Sebelumnya',
            '${ctx.previousValue} ${ctx.displayUnit} · ${ctx.previousStamp}',
          ),
        const SizedBox(height: 4),
        Text(ctx.note, style: AppTypography.caption),
      ],
    );
  }
}
