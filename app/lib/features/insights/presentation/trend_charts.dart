import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/day_chart.dart';
import '../data/trends.dart';

final _dayName = DateFormat('EEEE, d MMM', 'id_ID');
final _short = DateFormat('EEE', 'id_ID');

String _axisLabel(Trends t, int i) {
  final d = t.series[i].date;
  if (t.days <= 7) return _short.format(d);
  if (i == 0 || d.day == 1) return DateFormat('d MMM', 'id_ID').format(d);
  return '${d.day}';
}

double _niceMax(double v) {
  if (v <= 0) return 1;
  final mag = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
  for (final m in [1, 2, 2.5, 5, 10]) {
    if (v <= m * mag) return m * mag;
  }
  return 10 * mag;
}

// ───────────────────────── Konsistensi mencatat ─────────────────────────

class _CellsPainter extends DayPainter {
  const _CellsPainter(this.recorded);
  final List<bool> recorded;
  @override
  void paint(Canvas canvas, DayFrame f) {
    final w = math.max(f.slotW - (f.count > 30 ? 1 : 4), 1.5);
    final r = Radius.circular(math.min(7, w / 2));
    f.guide(canvas);
    for (var i = 0; i < f.count; i++) {
      final g = f.grow(i);
      final h = f.plot.height * (0.35 + 0.65 * g);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(f.centerX(i), f.plot.center.dy),
          width: w,
          height: h,
        ),
        r,
      );
      if (recorded[i]) {
        canvas.drawRRect(
          rect,
          Paint()
            ..color = i == f.selected
                ? AppColors.brand
                : AppColors.brand.withValues(alpha: 0.85),
        );
      } else if (w < 7) {
        // Sempit (30/90 hari): garis tepi 1 px hilang di layar; hari kosong = blok pucat, hari ada = blok pekat.
        canvas.drawRRect(
          rect,
          Paint()
            ..color = i == f.selected
                ? AppColors.decorative
                : AppColors.surfaceMuted,
        );
      } else {
        canvas.drawRRect(rect, Paint()..color = AppColors.surface);
        canvas.drawRRect(
          rect,
          Paint()
            ..color = AppColors.decorative.withValues(alpha: 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      }
    }
  }
}

class ConsistencyChart extends StatelessWidget {
  const ConsistencyChart({
    super.key,
    required this.trends,
    this.dimmed = false,
  });
  final Trends trends;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final t = trends;
    String detail(TrendDay d) {
      final parts = [
        if (d.mealCount > 0) '${d.mealCount} makan',
        if (d.glucoseCount != null) '${d.glucoseCount} pengukuran glukosa',
        if (d.activityMinutes != null) '${d.activityMinutes} menit aktivitas',
        if (d.medTaken + d.medSkipped > 0)
          '${d.medTaken + d.medSkipped} konfirmasi obat',
      ];
      return parts.isEmpty ? 'Tidak ada catatan' : parts.join(' · ');
    }

    return DayChart(
      count: t.series.length,
      height: 62,
      dimmed: dimmed,
      accent: AppColors.brand,
      dataKey: t,
      painter: _CellsPainter([for (final d in t.series) d.recorded]),
      summary:
          '${t.recordedDays} dari ${t.days} hari ada catatan. Setiap kotak adalah satu hari.',
      readout: (i) {
        final d = t.series[i];
        return DayReadout(
          value: d.recorded ? 'Ada catatan' : 'Tidak tercatat',
          label: _dayName.format(d.date),
          extra: d.recorded ? detail(d) : null,
        );
      },
      semanticFor: (i) =>
          '${_dayName.format(t.series[i].date)}: ${t.series[i].recorded ? detail(t.series[i]) : 'tidak tercatat'}',
      xLabel: (i) => _axisLabel(t, i),
    );
  }
}

// ───────────────────────────── Aktivitas ─────────────────────────────

class _BarsPainter extends DayPainter {
  const _BarsPainter(this.current, this.previous, this.maxV);
  final List<int?> current, previous;
  final double maxV;
  @override
  void paint(Canvas canvas, DayFrame f) {
    final base = f.plot.bottom;
    canvas.drawLine(
      Offset(f.plot.left, base),
      Offset(f.plot.right, base),
      Paint()
        ..color = AppColors.border
        ..strokeWidth = 1,
    );
    final top = f.text('${maxV.round()}', AppTypography.caption);
    top.paint(canvas, Offset(0, f.plot.top - 2));
    canvas.drawLine(
      Offset(f.plot.left, f.plot.top),
      Offset(f.plot.right, f.plot.top),
      Paint()
        ..color = AppColors.border.withValues(alpha: 0.6)
        ..strokeWidth = 1,
    );
    f.guide(canvas);
    final ghostW = math.max(f.slotW * 0.74, 2.0),
        barW = math.max(f.slotW * 0.44, 1.6);
    for (var i = 0; i < f.count; i++) {
      final g = f.grow(i);
      final p = previous[i];
      if (p != null) {
        final h = p / maxV * f.plot.height * g;
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(f.centerX(i) - ghostW / 2, base - h, ghostW, h),
            topLeft: const Radius.circular(4),
            topRight: const Radius.circular(4),
          ),
          Paint()..color = AppColors.decorative.withValues(alpha: 0.28),
        );
      }
      final c = current[i];
      if (c == null) {
        f.emptySlot(canvas, i);
      } else {
        final h = math.max(c / maxV * f.plot.height * g, 2.0);
        final sel = i == f.selected;
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(f.centerX(i) - barW / 2, base - h, barW, h),
            topLeft: Radius.circular(math.min(5, barW / 2)),
            topRight: Radius.circular(math.min(5, barW / 2)),
          ),
          Paint()
            ..color = sel
                ? AppColors.activityInk
                : AppColors.activityInk.withValues(alpha: 0.78),
        );
      }
    }
  }
}

class ActivityChart extends StatelessWidget {
  const ActivityChart({super.key, required this.trends, this.dimmed = false});
  final Trends trends;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final t = trends;
    final cur = [for (final d in t.series) d.activityMinutes];
    final prev = t.previousActivity;
    final maxV = _niceMax(
      [...cur, ...prev].whereType<int>().fold<int>(0, math.max).toDouble(),
    );
    String sem(int i) =>
        '${_dayName.format(t.series[i].date)}: ${cur[i] == null ? 'tidak ada sesi tercatat' : '${cur[i]} menit'}${prev[i] == null ? '' : ', periode sebelumnya ${prev[i]} menit'}';
    return DayChart(
      count: t.series.length,
      height: 150,
      leftInset: 30,
      dimmed: dimmed,
      accent: AppColors.activityInk,
      dataKey: t,
      painter: _BarsPainter(cur, prev, maxV),
      summary:
          'Menit aktivitas per hari selama ${t.days} hari${t.activityTotal == null ? ', belum ada sesi' : ', total ${t.activityTotal} menit'}. Batang abu adalah periode sebelumnya.',
      readout: (i) {
        final d = t.series[i];
        final isBest = cur[i] != null && cur[i] == t.bestActivityMinutes;
        return DayReadout(
          value: cur[i] == null ? 'Tidak ada sesi' : '${cur[i]} menit',
          label: _dayName.format(d.date),
          extra: [
            if (isBest) 'Terbanyak di rentang ini',
            if (prev[i] != null) 'sebelumnya ${prev[i]} menit',
          ].join(' · ').nullIfEmpty,
        );
      },
      semanticFor: sem,
      xLabel: (i) => _axisLabel(t, i),
    );
  }
}

// ───────────────────────────── Glukosa ─────────────────────────────

class _CapsulesPainter extends DayPainter {
  const _CapsulesPainter(this.mins, this.maxs, this.lo, this.hi, this.fmt);
  final List<double?> mins, maxs;
  final double lo, hi;
  final String Function(double) fmt;
  @override
  void paint(Canvas canvas, DayFrame f) {
    double y(double v) => f.plot.bottom - (v - lo) / (hi - lo) * f.plot.height;
    for (final v in [lo, hi]) {
      canvas.drawLine(
        Offset(f.plot.left, y(v)),
        Offset(f.plot.right, y(v)),
        Paint()
          ..color = AppColors.border
          ..strokeWidth = 1,
      );
      final tp = f.text(fmt(v), AppTypography.caption);
      tp.paint(canvas, Offset(0, y(v) - tp.height / 2));
    }
    f.guide(canvas);
    final w = math.min(math.max(f.slotW * 0.5, 2.0), 12.0);
    for (var i = 0; i < f.count; i++) {
      final a = mins[i], b = maxs[i];
      if (a == null || b == null) {
        f.emptySlot(canvas, i);
        continue;
      }
      final g = f.grow(i);
      final mid = (y(a) + y(b)) / 2;
      final half = math.max((y(a) - y(b)) / 2, 5.0) * g;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(f.centerX(i), mid),
          width: w,
          height: half * 2,
        ),
        Radius.circular(w / 2),
      );
      final sel = i == f.selected;
      canvas.drawRRect(
        rect,
        Paint()
          ..color = sel
              ? AppColors.glucoseInk.withValues(alpha: 0.35)
              : AppColors.glucoseTint,
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = AppColors.glucoseInk
          ..style = PaintingStyle.stroke
          ..strokeWidth = sel ? 2.2 : 1.5,
      );
    }
  }
}

class GlucoseChart extends StatelessWidget {
  const GlucoseChart({
    super.key,
    required this.trends,
    required this.unit,
    this.dimmed = false,
  });
  final Trends trends;
  final String unit;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final t = trends;
    final mmol = unit == 'mmol/L';
    double conv(double v) => mmol ? v / 18.016 : v;
    String fmt(double v) => conv(v).toStringAsFixed(mmol ? 1 : 0);
    final mins = [for (final d in t.series) d.glucoseMin];
    final maxs = [for (final d in t.series) d.glucoseMax];
    final known = [...mins, ...maxs].whereType<double>();
    final lo = known.isEmpty
        ? 0.0
        : (known.reduce(math.min) / 10).floorToDouble() * 10 - 10;
    final hi = known.isEmpty
        ? 1.0
        : (known.reduce(math.max) / 10).ceilToDouble() * 10 + 10;
    String value(TrendDay d) => d.glucoseMin == d.glucoseMax
        ? '${fmt(d.glucoseMin!)} $unit'
        : '${fmt(d.glucoseMin!)}–${fmt(d.glucoseMax!)} $unit';
    return DayChart(
      count: t.series.length,
      height: 150,
      leftInset: mmol ? 30 : 34,
      dimmed: dimmed,
      accent: AppColors.glucoseInk,
      dataKey: t,
      painter: _CapsulesPainter(mins, maxs, lo, hi, fmt),
      summary:
          '${t.glucoseReadings} pengukuran glukosa pada ${t.glucoseDays} dari ${t.days} hari. Setiap kapsul adalah rentang pengukuran satu hari.',
      readout: (i) {
        final d = t.series[i];
        if (d.glucoseCount == null) {
          return DayReadout(
            value: 'Tidak ada pengukuran',
            label: _dayName.format(d.date),
          );
        }
        return DayReadout(
          value: value(d),
          label: _dayName.format(d.date),
          extra: '${d.glucoseCount} pengukuran',
        );
      },
      semanticFor: (i) {
        final d = t.series[i];
        return '${_dayName.format(d.date)}: ${d.glucoseCount == null ? 'tidak ada pengukuran' : '${value(d)}, ${d.glucoseCount} pengukuran'}';
      },
      xLabel: (i) => _axisLabel(t, i),
    );
  }
}

// ───────────────────────────── Makan (karbohidrat) ─────────────────────────────

class _CarbPainter extends DayPainter {
  const _CarbPainter(this.carbs, this.coverage, this.meals, this.maxV);
  final List<double?> carbs;
  final List<String?> coverage;
  final List<int> meals;
  final double maxV;
  @override
  void paint(Canvas canvas, DayFrame f) {
    final base = f.plot.bottom;
    canvas.drawLine(
      Offset(f.plot.left, base),
      Offset(f.plot.right, base),
      Paint()
        ..color = AppColors.border
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(f.plot.left, f.plot.top),
      Offset(f.plot.right, f.plot.top),
      Paint()
        ..color = AppColors.border.withValues(alpha: 0.6)
        ..strokeWidth = 1,
    );
    f
        .text('${maxV.round()}', AppTypography.caption)
        .paint(canvas, Offset(0, f.plot.top - 2));
    f.guide(canvas);
    final barW = math.max(f.slotW * 0.5, 1.6);
    for (var i = 0; i < f.count; i++) {
      final c = carbs[i];
      if (meals[i] == 0) {
        f.emptySlot(canvas, i);
        continue;
      }
      final g = f.grow(i);
      if (c == null) {
        // Ada makan tetapi tak satu pun item punya data karbohidrat: tanda tanya, bukan batang nol.
        final tp = f.text(
          '?',
          AppTypography.caption.copyWith(
            color: AppColors.mealInk,
            fontWeight: FontWeight.w700,
          ),
        );
        tp.paint(
          canvas,
          Offset(f.centerX(i) - tp.width / 2, base - tp.height - 2),
        );
        continue;
      }
      final h = math.max(c / maxV * f.plot.height * g, 2.0);
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(f.centerX(i) - barW / 2, base - h, barW, h),
        topLeft: Radius.circular(math.min(5, barW / 2)),
        topRight: Radius.circular(math.min(5, barW / 2)),
      );
      final sel = i == f.selected;
      if (coverage[i] == 'COMPLETE') {
        canvas.drawRRect(
          rect,
          Paint()
            ..color = sel
                ? AppColors.mealInk
                : AppColors.mealInk.withValues(alpha: 0.8),
        );
      } else {
        // Sebagian item tak punya data: batang berongga = "setidaknya sebesar ini".
        canvas.drawRRect(rect, Paint()..color = AppColors.mealTint);
        canvas.drawRRect(
          rect,
          Paint()
            ..color = AppColors.mealInk
            ..style = PaintingStyle.stroke
            ..strokeWidth = sel ? 2.2 : 1.5,
        );
      }
    }
  }
}

String _covLabel(String? c) => switch (c) {
  'COMPLETE' => 'lengkap',
  'PARTIAL' => 'sebagian item',
  _ => 'tidak diketahui',
};

class MealChart extends StatelessWidget {
  const MealChart({super.key, required this.trends, this.dimmed = false});
  final Trends trends;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final t = trends;
    final carbs = [for (final d in t.series) d.carbs];
    final cov = [for (final d in t.series) d.carbsCoverage];
    final meals = [for (final d in t.series) d.mealCount];
    final maxV = _niceMax(carbs.whereType<double>().fold<double>(0, math.max));
    String num1(double v) => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);
    String detail(int i) {
      final d = t.series[i];
      if (d.mealCount == 0) return 'tidak ada catatan makan';
      final c = d.carbs;
      return '${d.mealCount} makan, ${c == null ? 'karbohidrat tidak diketahui' : 'karbohidrat tercatat ${num1(c)} g (${_covLabel(d.carbsCoverage)})'}';
    }

    return DayChart(
      count: t.series.length,
      height: 150,
      leftInset: 30,
      dimmed: dimmed,
      accent: AppColors.mealInk,
      dataKey: t,
      painter: _CarbPainter(carbs, cov, meals, maxV),
      summary:
          'Karbohidrat yang tercatat per hari selama ${t.days} hari. Batang berongga berarti hanya sebagian item makan yang punya data.',
      readout: (i) {
        final d = t.series[i];
        if (d.mealCount == 0) {
          return DayReadout(
            value: 'Tidak ada catatan makan',
            label: _dayName.format(d.date),
          );
        }
        return DayReadout(
          value: d.carbs == null
              ? 'Karbohidrat tidak diketahui'
              : '${num1(d.carbs!)} g karbohidrat',
          label: _dayName.format(d.date),
          extra: '${d.mealCount} makan · ${_covLabel(d.carbsCoverage)}',
        );
      },
      semanticFor: (i) => '${_dayName.format(t.series[i].date)}: ${detail(i)}',
      xLabel: (i) => _axisLabel(t, i),
    );
  }
}

// ───────────────────────────── Obat ─────────────────────────────

class _MedPainter extends DayPainter {
  const _MedPainter(this.taken, this.skipped, this.maxV);
  final List<int> taken, skipped;
  final int maxV;
  @override
  void paint(Canvas canvas, DayFrame f) {
    final base = f.plot.bottom;
    canvas.drawLine(
      Offset(f.plot.left, base),
      Offset(f.plot.right, base),
      Paint()
        ..color = AppColors.border
        ..strokeWidth = 1,
    );
    f.guide(canvas);
    final w = math.max(f.slotW * 0.5, 1.6);
    final unit = (f.plot.height - 6) / maxV;
    for (var i = 0; i < f.count; i++) {
      final tk = taken[i], sk = skipped[i];
      if (tk + sk == 0) {
        f.emptySlot(canvas, i);
        continue;
      }
      final g = f.grow(i);
      final sel = i == f.selected;
      var y = base;
      if (tk > 0) {
        final h = tk * unit * g;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(f.centerX(i) - w / 2, y - h, w, h),
            Radius.circular(math.min(4, w / 2)),
          ),
          Paint()
            ..color = sel
                ? AppColors.medicationInk
                : AppColors.medicationInk.withValues(alpha: 0.82),
        );
        y -= h + 2;
      }
      if (sk > 0) {
        // Dilewati = berongga, bukan warna "buruk": ini kejadian yang dicatat, bukan kegagalan.
        final h = sk * unit * g;
        final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(f.centerX(i) - w / 2, y - h, w, h),
          Radius.circular(math.min(4, w / 2)),
        );
        canvas.drawRRect(r, Paint()..color = AppColors.medicationTint);
        canvas.drawRRect(
          r,
          Paint()
            ..color = AppColors.medicationInk
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3,
        );
      }
    }
  }
}

class MedicationChart extends StatelessWidget {
  const MedicationChart({super.key, required this.trends, this.dimmed = false});
  final Trends trends;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final t = trends;
    final taken = [for (final d in t.series) d.medTaken];
    final skipped = [for (final d in t.series) d.medSkipped];
    final maxV = [
      for (var i = 0; i < taken.length; i++) taken[i] + skipped[i],
    ].fold<int>(1, math.max);
    String detail(int i) {
      if (taken[i] + skipped[i] == 0) return 'tidak ada konfirmasi tercatat';
      return [
        if (taken[i] > 0) '${taken[i]} diminum',
        if (skipped[i] > 0) '${skipped[i]} dilewati',
      ].join(', ');
    }

    return DayChart(
      count: t.series.length,
      height: 110,
      dimmed: dimmed,
      accent: AppColors.medicationInk,
      dataKey: t,
      painter: _MedPainter(taken, skipped, maxV),
      summary:
          'Konfirmasi obat per hari selama ${t.days} hari. Batang pekat = diminum, berongga = dilewati. Bukan skor kepatuhan.',
      readout: (i) {
        final d = t.series[i];
        if (taken[i] + skipped[i] == 0) {
          return DayReadout(
            value: 'Tidak ada konfirmasi',
            label: _dayName.format(d.date),
          );
        }
        return DayReadout(value: detail(i), label: _dayName.format(d.date));
      },
      semanticFor: (i) => '${_dayName.format(t.series[i].date)}: ${detail(i)}',
      xLabel: (i) => _axisLabel(t, i),
    );
  }
}

// ───────────────────────────── Tabel pendamping ─────────────────────────────

/// Setiap grafik punya kembaran tabel: nilai tidak pernah hanya bisa dibaca lewat sentuhan.
class ChartTableToggle extends StatefulWidget {
  const ChartTableToggle({
    super.key,
    required this.headers,
    required this.rows,
  });
  final List<String> headers;
  final List<List<String>> rows;
  @override
  State<ChartTableToggle> createState() => _ChartTableToggleState();
}

class _ChartTableToggleState extends State<ChartTableToggle> {
  bool open = false;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextButton.icon(
        onPressed: () => setState(() => open = !open),
        icon: Icon(
          open ? Icons.expand_less_rounded : Icons.table_rows_rounded,
          size: 18,
        ),
        label: Text(open ? 'Sembunyikan tabel' : 'Lihat sebagai tabel'),
      ),
      if (open)
        Table(
          columnWidths: const {0: FlexColumnWidth(1.6)},
          border: TableBorder(
            horizontalInside: BorderSide(color: AppColors.border),
          ),
          children: [
            TableRow(
              children: [
                for (final h in widget.headers)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      h,
                      style: AppTypography.caption.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            for (final r in widget.rows)
              TableRow(
                children: [
                  for (final c in r)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(c, style: AppTypography.secondary),
                    ),
                ],
              ),
          ],
        ),
    ],
  );
}

/// Kotak ringkas satu angka besar + keterangan (stat tile): angka adalah grafiknya bila hanya satu nilai.
class HeroFigure extends StatelessWidget {
  const HeroFigure({
    super.key,
    required this.value,
    required this.label,
    this.sub,
  });
  final String value, label;
  final String? sub;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTypography.secondaryStrong),
      const SizedBox(height: 2),
      Text(value, style: AppTypography.headline),
      if (sub != null)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(sub!, style: AppTypography.secondary),
        ),
      const SizedBox(height: AppSpacing.xs),
    ],
  );
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

// Dipakai tabel di layar tren.
List<List<String>> activityRows(Trends t) => [
  for (var i = 0; i < t.series.length; i++)
    [
      _dayName.format(t.series[i].date),
      t.series[i].activityMinutes?.toString() ?? '–',
      t.previousActivity[i]?.toString() ?? '–',
    ],
];

List<List<String>> glucoseRows(Trends t, String unit) {
  final mmol = unit == 'mmol/L';
  String f(double? v) =>
      v == null ? '–' : (mmol ? v / 18.016 : v).toStringAsFixed(mmol ? 1 : 0);
  return [
    for (final d in t.series)
      [
        _dayName.format(d.date),
        f(d.glucoseMin),
        f(d.glucoseMax),
        d.glucoseCount?.toString() ?? '–',
      ],
  ];
}

List<List<String>> consistencyRows(Trends t) => [
  for (final d in t.series)
    [
      _dayName.format(d.date),
      d.recorded ? 'Ada' : 'Tidak tercatat',
      '${d.mealCount}',
      d.glucoseCount?.toString() ?? '–',
    ],
];

List<List<String>> mealRows(Trends t) => [
  for (final d in t.series)
    [
      _dayName.format(d.date),
      d.mealCount == 0 ? '–' : '${d.mealCount}',
      d.carbs == null ? '–' : d.carbs!.toStringAsFixed(1),
      d.mealCount == 0 ? '–' : _covLabel(d.carbsCoverage),
    ],
];

List<List<String>> medicationRows(Trends t) => [
  for (final d in t.series)
    [
      _dayName.format(d.date),
      d.medTaken + d.medSkipped == 0 ? '–' : '${d.medTaken}',
      d.medTaken + d.medSkipped == 0 ? '–' : '${d.medSkipped}',
    ],
];
