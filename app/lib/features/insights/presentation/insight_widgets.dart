import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/domain_style.dart';
import '../application/insights_controller.dart';
import '../data/statistics.dart';
import 'insight_presentation.dart';
import 'nutrition_chart.dart';

const statisticsPeriods = [7, 14, 30, 90];
final _range = DateFormat('d MMM y', 'id_ID');
final _time = DateFormat('HH.mm', 'id_ID');
final _dayTime = DateFormat('d MMM, HH.mm', 'id_ID');

DomainStyle domainStyleFor(String domain) => switch (domain) {
  'nutrition' => DomainStyle.meal,
  'activity' => DomainStyle.activity,
  'glucose' => DomainStyle.glucose,
  'medication' => DomainStyle.medication,
  _ => DomainStyle.goal,
};

bool largeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) > 13.5;

String updatedLabel(DateTime at) {
  final local = at.toLocal();
  final now = DateTime.now();
  final sameDay =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  return sameDay ? _time.format(local) : _dayTime.format(local);
}

class SectionTabs extends StatelessWidget {
  const SectionTabs({
    super.key,
    required this.labels,
    required this.value,
    required this.onChanged,
  });

  final List<String> labels;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == value,
                label: labels[i],
                excludeSemantics: true,
                onTap: () => onChanged(i),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: reduce
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    constraints: const BoxConstraints(
                      minHeight: AppSpacing.minTouchTarget - 4,
                    ),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: i == value
                          ? AppColors.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: i == value
                          ? Border.all(color: AppColors.border)
                          : null,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        labels[i],
                        maxLines: 1,
                        style: AppTypography.secondaryStrong.copyWith(
                          color: i == value
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontWeight: i == value
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PeriodSelector extends ConsumerWidget {
  const PeriodSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(trendRangeProvider);
    final perRow = largeText(context) ? 2 : 4;
    const gap = AppSpacing.xs;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final p in statisticsPeriods)
              SizedBox(
                width: width,
                child: _PeriodChip(
                  label: '$p hari',
                  selected: p == days,
                  onTap: () => ref.read(trendRangeProvider.notifier).set(p),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: Material(
      color: selected ? AppColors.primary : AppColors.surface,
      shape: StadiumBorder(
        side: selected ? BorderSide.none : BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTouchTarget,
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: AppTypography.secondaryStrong.copyWith(
                    color: selected
                        ? AppColors.onPrimary
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class DataQualityHint extends StatelessWidget {
  const DataQualityHint({
    super.key,
    required this.have,
    required this.total,
    this.label,
  });

  final int have, total;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final text = label ?? coverageSentence(have, total);
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Row(
        children: [
          if (total <= 31)
            Flexible(
              flex: 0,
              child: Wrap(
                spacing: 3,
                runSpacing: 3,
                children: [
                  for (var i = 0; i < total; i++)
                    Container(
                      height: 6,
                      width: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < have
                            ? AppColors.brand
                            : AppColors.disabled.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
            )
          else
            SizedBox(
              width: 72,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : have / total,
                  minHeight: 6,
                  color: AppColors.brand,
                  backgroundColor: AppColors.disabled.withValues(alpha: 0.6),
                ),
              ),
            ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(text, style: AppTypography.caption)),
        ],
      ),
    );
  }
}

class _Kicker extends StatelessWidget {
  const _Kicker({required this.domain, required this.label});
  final String domain, label;

  @override
  Widget build(BuildContext context) {
    final style = domainStyleFor(domain);
    return Row(
      children: [
        Container(
          height: 24,
          width: 24,
          decoration: BoxDecoration(color: style.tint, shape: BoxShape.circle),
          child: Icon(style.icon, size: 14, color: style.ink),
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            label,
            style: AppTypography.secondaryStrong.copyWith(color: style.ink),
          ),
        ),
      ],
    );
  }
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.onTap, this.padding = 16});
  final Widget child;
  final VoidCallback? onTap;
  final double padding;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg - 2),
      side: BorderSide(color: AppColors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: EdgeInsets.all(padding), child: child),
    ),
  );
}

class InsightCard extends StatelessWidget {
  const InsightCard({
    super.key,
    required this.insight,
    required this.onOpen,
    required this.onAction,
  });

  final InsightPresentation insight;
  final VoidCallback onOpen;
  final ValueChanged<InsightAction> onAction;

  @override
  Widget build(BuildContext context) {
    final action = insight.action;
    return _Surface(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Kicker(domain: insight.domain, label: insight.category),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            header: true,
            child: Text(insight.headline, style: AppTypography.title),
          ),
          const SizedBox(height: 2),
          Text(insight.supporting, style: AppTypography.secondary),
          if (action != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => onAction(action),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, AppSpacing.minTouchTarget),
                  backgroundColor: Colors.transparent,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: Text(action.label)),
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right_rounded, size: 20),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.metric, required this.onTap});
  final MetricPresentation metric;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = metric;
    final style = domainStyleFor(m.domain);
    return Semantics(
      button: true,
      label:
          '${m.label}: ${m.value == null ? '' : '${m.value}${m.unit == null ? '' : ' ${m.unit}'}. '}${m.caption}. Ketuk untuk detail.',
      excludeSemantics: true,
      onTap: onTap,
      child: _Surface(
        onTap: onTap,
        padding: 14,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 24,
                  width: 24,
                  decoration: BoxDecoration(
                    color: style.tint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(style.icon, size: 14, color: style.ink),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(m.label, style: AppTypography.secondaryStrong),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            if (m.hasValue)
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: m.value,
                      style: AppTypography.metric.copyWith(fontSize: 24),
                    ),
                    if (m.unit != null)
                      TextSpan(
                        text: ' ${m.unit}',
                        style: AppTypography.secondary,
                      ),
                  ],
                ),
              ),
            Text(
              m.caption,
              style: m.hasValue
                  ? AppTypography.caption
                  : AppTypography.secondary,
            ),
          ],
        ),
      ),
    );
  }
}

class MetricGrid extends StatelessWidget {
  const MetricGrid({super.key, required this.metrics, required this.onOpen});
  final List<MetricPresentation> metrics;
  final ValueChanged<MetricPresentation> onOpen;

  @override
  Widget build(BuildContext context) {
    if (largeText(context)) {
      return Column(
        children: [
          for (final m in metrics) ...[
            MetricTile(metric: m, onTap: () => onOpen(m)),
            const SizedBox(height: AppSpacing.xs),
          ],
        ],
      );
    }
    final rows = <Widget>[];
    for (var i = 0; i < metrics.length; i += 2) {
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: MetricTile(
                  metric: metrics[i],
                  onTap: () => onOpen(metrics[i]),
                ),
              ),
              const SizedBox(width: AppSpacing.xs + 2),
              Expanded(
                child: i + 1 < metrics.length
                    ? MetricTile(
                        metric: metrics[i + 1],
                        onTap: () => onOpen(metrics[i + 1]),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
      if (i + 2 < metrics.length) {
        rows.add(const SizedBox(height: AppSpacing.xs + 2));
      }
    }
    return Column(children: rows);
  }
}

Future<void> _sheet(
  BuildContext context,
  List<Widget> Function(BuildContext) children,
) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: AppColors.surface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.hero)),
  ),
  builder: (sheet) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.7,
    minChildSize: 0.4,
    maxChildSize: 0.95,
    builder: (context, controller) => ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: children(sheet),
    ),
  ),
);

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs + 2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.secondaryStrong),
        const SizedBox(height: 2),
        Text(value, style: AppTypography.body),
      ],
    ),
  );
}

class _Bullets extends StatelessWidget {
  const _Bullets(this.items);
  final List<String> items;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final l in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('• $l', style: AppTypography.secondary),
          ),
      ],
    ),
  );
}

class AboutDataSection extends StatelessWidget {
  const AboutDataSection({
    super.key,
    required this.statistics,
    required this.updatedAt,
  });
  final List<Statistic> statistics;
  final DateTime updatedAt;

  @override
  Widget build(BuildContext context) {
    final s = statistics.first;
    final limits = {for (final st in statistics) ...st.limitations}.toList();
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text('Tentang data', style: AppTypography.bodyStrong),
        children: [
          _Field('Sumber', sourceLabel(s.sourceType)),
          for (final (label, derivation) in _derivations(statistics))
            _Field(label, derivation),
          _Field(
            'Periode',
            '${_range.format(DateTime.parse(s.rangeStart))} – ${_range.format(DateTime.parse(s.rangeEnd))}',
          ),
          _Field('Terakhir diperbarui', updatedLabel(updatedAt)),
          if (limits.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            _Bullets(limits),
          ],
        ],
      ),
    );
  }
}

List<(String, String)> _derivations(List<Statistic> statistics) {
  final groups = <String, List<Statistic>>{};
  for (final st in statistics) {
    groups.putIfAbsent(st.derivation, () => []).add(st);
  }
  if (groups.length == 1) return [('Cara hitung', groups.keys.first)];
  return [
    for (final e in groups.entries)
      (
        e.value.length > 1
            ? 'Rata-rata per hari tercatat'
            : e.value.first.label,
        e.key,
      ),
  ];
}

const _nutrients = [
  ('nutrition.calories_per_logged_day', 'Energi'),
  ('nutrition.carbohydrates_per_logged_day', 'Karbohidrat'),
  ('nutrition.protein_per_logged_day', 'Protein'),
  ('nutrition.fat_per_logged_day', 'Lemak'),
  ('nutrition.fiber_per_logged_day', 'Serat'),
];

Future<void> showMetricDetail(
  BuildContext context, {
  required Statistics stats,
  required MetricPresentation metric,
  required String? actionLabel,
  required VoidCallback? onAction,
}) {
  final st = metric.statistic;
  return _sheet(context, (sheet) {
    final related = <Statistic>[?st];
    final out = <Widget>[
      _Kicker(
        domain: metric.domain,
        label: '${metric.label} · ${stats.days} hari terakhir',
      ),
      const SizedBox(height: AppSpacing.sm),
    ];
    if (metric.hasValue) {
      out.add(
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: metric.value, style: AppTypography.metricLarge),
              if (metric.unit != null)
                TextSpan(
                  text: ' ${metric.unit}',
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      );
    }
    out.add(Text(metric.caption, style: AppTypography.secondary));
    if (st != null) {
      final validity = comparisonValidity(st);
      final cmp = comparisonSentence(st, stats.days, withPrevious: true);
      if (cmp != null) {
        out.addAll([
          const SizedBox(height: AppSpacing.sm),
          Text(cmp, style: AppTypography.body),
        ]);
      } else if (validity == ComparisonValidity.tooLittleData) {
        out.addAll([
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Belum dibandingkan: data periode ini masih sedikit.',
            style: AppTypography.body,
          ),
        ]);
      }
      if (st.daysWithData < st.totalDays && st.totalDays > 0) {
        out.addAll([
          const SizedBox(height: AppSpacing.sm),
          DataQualityHint(
            have: st.daysWithData,
            total: st.totalDays,
            label:
                'Data ada untuk ${st.daysWithData} dari ${st.totalDays} hari',
          ),
        ]);
      }
    }
    if (metric.domain == 'medication' && st?.detail != null) {
      final d = st!.detail!;
      out.addAll([
        const SizedBox(height: AppSpacing.sm),
        _Field(
          'Rincian',
          'Diminum ${d['taken']?.round() ?? 0} · dilewati ${d['skipped']?.round() ?? 0} · belum dikonfirmasi ${d['unconfirmed']?.round() ?? 0}',
        ),
        Text(
          'Belum dikonfirmasi tidak berarti terlewat.',
          style: AppTypography.secondary,
        ),
      ]);
    }
    if (metric.domain == 'nutrition') {
      out.addAll([
        const SizedBox(height: AppSpacing.md),
        Text('Makronutrien tercatat', style: AppTypography.bodyStrong),
        const SizedBox(height: AppSpacing.xs),
        NutritionStackChart(stats: stats),
        const SizedBox(height: AppSpacing.md),
        Text('Rata-rata per hari tercatat', style: AppTypography.bodyStrong),
      ]);
      for (final (id, name) in _nutrients) {
        final n = stats.byId(id);
        if (n == null) continue;
        related.add(n);
        final value = n.ready && n.value != null
            ? '${formatValue(n.value!, whole: n.unit == 'kkal')} ${n.unit}${n.coverageStatus == 'PARTIAL' ? ' · sebagian' : ''}'
            : 'Belum cukup data';
        out.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(child: Text(name, style: AppTypography.body)),
                Text(
                  value,
                  style: n.ready
                      ? AppTypography.bodyStrong
                      : AppTypography.secondary,
                ),
              ],
            ),
          ),
        );
      }
    }
    if (metric.domain == 'glucose') {
      out.addAll([
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Ini ringkasan catatanmu, bukan penilaian medis. Bicarakan pola yang mengkhawatirkan dengan tenaga kesehatanmu.',
          style: AppTypography.secondary,
        ),
      ]);
    }
    if (actionLabel != null && onAction != null) {
      out.addAll([
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: () {
              Navigator.of(sheet).pop();
              onAction();
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              minimumSize: const Size(0, AppSpacing.minTouchTarget),
              shape: const StadiumBorder(),
            ),
            child: Text(actionLabel),
          ),
        ),
      ]);
    }
    if (related.isNotEmpty) {
      out.addAll([
        const SizedBox(height: AppSpacing.md),
        Divider(color: AppColors.border, height: 1),
        AboutDataSection(statistics: related, updatedAt: stats.computedAt),
      ]);
    }
    return out;
  });
}

Future<void> showInsightDetail(
  BuildContext context, {
  required Statistics stats,
  required InsightPresentation insight,
  required ValueChanged<InsightAction> onAction,
}) {
  final related = [
    for (final id in insight.source.statisticIds) ?stats.byId(id),
  ];
  final c = insight.source;
  return _sheet(
    context,
    (sheet) => [
      _Kicker(domain: insight.domain, label: insight.category),
      const SizedBox(height: AppSpacing.sm),
      Semantics(
        header: true,
        child: Text(insight.headline, style: AppTypography.heading),
      ),
      const SizedBox(height: AppSpacing.xxs),
      Text(insight.supporting, style: AppTypography.body),
      if (c.evidence.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.sm),
        for (final e in c.evidence)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(e.label, style: AppTypography.secondary)),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    e.value,
                    textAlign: TextAlign.end,
                    style: AppTypography.bodyStrong,
                  ),
                ),
              ],
            ),
          ),
      ],
      if (c.daysWithData < c.totalDays) ...[
        const SizedBox(height: AppSpacing.sm),
        DataQualityHint(
          have: c.daysWithData,
          total: c.totalDays,
          label: 'Data ada untuk ${c.daysWithData} dari ${c.totalDays} hari',
        ),
      ],
      if (insight.action case final a?) ...[
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: () {
              Navigator.of(sheet).pop();
              onAction(a);
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              minimumSize: const Size(0, AppSpacing.minTouchTarget),
              shape: const StadiumBorder(),
            ),
            child: Text(a.label),
          ),
        ),
      ],
      if (related.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        Divider(color: AppColors.border, height: 1),
        AboutDataSection(statistics: related, updatedAt: stats.computedAt),
      ],
    ],
  );
}

Future<void> showAboutWawasan(
  BuildContext context, {
  DateTime? updatedAt,
}) => _sheet(
  context,
  (sheet) => [
    Semantics(
      header: true,
      child: Text('Tentang data di Wawasan', style: AppTypography.heading),
    ),
    const SizedBox(height: AppSpacing.sm),
    const _Bullets([
      'Semua angka berasal dari catatanmu sendiri.',
      'Hari tanpa catatan ditandai — dan tidak dihitung sebagai nol.',
      'Perbandingan hanya dengan catatanmu pada periode sebelumnya.',
      'Wawasan ini bukan diagnosis atau saran medis. Bicarakan pola yang mengkhawatirkan dengan tenaga kesehatanmu.',
    ]),
    if (updatedAt != null) ...[
      const SizedBox(height: AppSpacing.sm),
      Text(
        'Terakhir diperbarui ${updatedLabel(updatedAt)}',
        style: AppTypography.caption,
      ),
    ],
  ],
);
