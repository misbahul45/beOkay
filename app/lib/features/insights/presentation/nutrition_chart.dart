import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/day_chart.dart';
import '../data/statistics.dart';
import 'trend_charts.dart' show ChartTableToggle;

const macroKeys = ['carbohydrates', 'protein', 'fat'];
const macroLabels = {
  'carbohydrates': 'Karbohidrat',
  'protein': 'Protein',
  'fat': 'Lemak',
};
Map<String, Color> get macroColors => {
  'carbohydrates': AppColors.mealSolid,
  'protein': AppColors.glucoseSolid,
  'fat': AppColors.goalSolid,
};

final _dayName = DateFormat('EEEE, d MMM', 'id_ID');
final _short = DateFormat('EEE', 'id_ID');
final _num = NumberFormat.decimalPattern('id_ID')..maximumFractionDigits = 1;

String formatGrams(double v) => _num.format(v);

double niceMax(double v) {
  if (v <= 0) return 1;
  final mag = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
  for (final m in [1, 2, 2.5, 5, 10]) {
    if (v <= m * mag) return m * mag;
  }
  return 10 * mag;
}

double? macroTotal(StatDay d) {
  if (d.meals == 0) return null;
  final known = [for (final k in macroKeys) d.grams(k)].whereType<double>();
  return known.isEmpty ? null : known.fold<double>(0, (s, v) => s + v);
}

class _MacroPainter extends DayPainter {
  const _MacroPainter(this.days, this.maxV);
  final List<StatDay> days;
  final double maxV;

  @override
  void paint(Canvas canvas, DayFrame f) {
    final base = f.plot.bottom;
    final line = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(f.plot.left, base),
      Offset(f.plot.right, base),
      line,
    );
    canvas.drawLine(
      Offset(f.plot.left, f.plot.top),
      Offset(f.plot.right, f.plot.top),
      line..color = AppColors.border.withValues(alpha: 0.6),
    );
    f
        .text(_num.format(maxV), AppTypography.caption)
        .paint(canvas, Offset(0, f.plot.top - 2));
    f.guide(canvas);
    final w = math.max(f.slotW * 0.5, 2.0);
    for (var i = 0; i < f.count; i++) {
      final d = days[i];
      if (macroTotal(d) == null) {
        f.emptySlot(canvas, i);
        continue;
      }
      final g = f.grow(i);
      var y = base;
      for (final k in macroKeys) {
        final v = d.grams(k);
        if (v == null || v <= 0) continue;
        final h = v / maxV * f.plot.height * g;
        canvas.drawRect(
          Rect.fromLTWH(f.centerX(i) - w / 2, y - h, w, math.max(h - 1, 0.5)),
          Paint()
            ..color = i == f.selected
                ? macroColors[k]!
                : macroColors[k]!.withValues(alpha: 0.82),
        );
        y -= h;
      }
    }
  }
}

class NutritionStackChart extends StatelessWidget {
  const NutritionStackChart({super.key, required this.stats});
  final Statistics stats;

  String _part(StatDay d, String k) {
    final v = d.nutrients[k];
    if (v == null || v.value == null) {
      return '${macroLabels[k]} tidak diketahui';
    }
    final partial = v.coverage == 'PARTIAL' ? ' (sebagian)' : '';
    return '${macroLabels[k]} ${formatGrams(v.value!)} g$partial';
  }

  String _describe(StatDay d) {
    if (d.meals == 0) return 'tidak ada catatan makan';
    if (macroTotal(d) == null) {
      return '${d.meals} catatan makan, gizinya tidak diketahui';
    }
    return macroKeys.map((k) => _part(d, k)).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final days = stats.series;
    final maxV = niceMax(
      days.map(macroTotal).whereType<double>().fold<double>(0, math.max),
    );
    final logged = days.where((d) => d.meals > 0).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DayChart(
          count: days.length,
          height: 150,
          leftInset: 30,
          accent: AppColors.mealInk,
          dataKey: stats,
          painter: _MacroPainter(days, maxV),
          summary:
              'Gram karbohidrat, protein, dan lemak tercatat per hari selama ${stats.days} hari. Ada catatan makan di $logged hari.',
          readout: (i) {
            final d = days[i];
            final total = macroTotal(d);
            return DayReadout(
              value: d.meals == 0
                  ? 'Tidak ada catatan makan'
                  : total == null
                  ? 'Gizi tidak diketahui'
                  : '${formatGrams(total)} g makronutrien',
              label: _dayName.format(d.date),
              extra: d.meals == 0 || total == null
                  ? null
                  : macroKeys
                        .where((k) => d.grams(k) != null)
                        .map(
                          (k) =>
                              '${macroLabels[k]} ${formatGrams(d.grams(k)!)} g',
                        )
                        .join(' · '),
            );
          },
          semanticFor: (i) =>
              '${_dayName.format(days[i].date)}: ${_describe(days[i])}',
          xLabel: (i) {
            final d = days[i].date;
            if (stats.days <= 7) return _short.format(d);
            if (i == 0 || d.day == 1) {
              return DateFormat('d MMM', 'id_ID').format(d);
            }
            return stats.days <= 14
                ? '${d.day}'
                : (i % 5 == 0 ? '${d.day}' : null);
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xxs,
          children: [
            for (final k in macroKeys)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 10,
                    width: 10,
                    decoration: BoxDecoration(
                      color: macroColors[k],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(macroLabels[k]!, style: AppTypography.caption),
                ],
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Batang dimulai dari nol. "–" berarti tidak ada catatan makan, bukan nol. Hanya item dengan berat dan nilai gizi yang dijumlahkan.',
          style: AppTypography.caption,
        ),
        ChartTableToggle(
          headers: const ['Tanggal', 'Karbo (g)', 'Protein (g)', 'Lemak (g)'],
          rows: [
            for (final d in days)
              [
                DateFormat('d MMM', 'id_ID').format(d.date),
                for (final k in macroKeys)
                  d.meals == 0
                      ? '–'
                      : d.grams(k) == null
                      ? 'tidak diketahui'
                      : formatGrams(d.grams(k)!),
              ],
          ],
        ),
      ],
    );
  }
}
