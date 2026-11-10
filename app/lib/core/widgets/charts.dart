import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// One slot of a [BarChart]. `value == null` means "no record", which is NOT zero:
/// it is drawn as a dashed empty slot with a dash label, so a missing day never looks like a measured 0.
class BarSlot {
  const BarSlot({required this.label, required this.value});
  final String label;
  final num? value;
}

/// Bars start at zero, every bar carries its value, and the whole chart has one spoken summary.
class BarChart extends StatelessWidget {
  const BarChart({
    super.key,
    required this.slots,
    required this.unit,
    required this.color,
    required this.tint,
    required this.semanticLabel,
    this.height = 140,
  });

  final List<BarSlot> slots;
  final String unit;
  final Color color, tint;
  final String semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: true,
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _BarPainter(
              slots,
              color,
              tint,
              MediaQuery.textScalerOf(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.slots, this.color, this.tint, this.scaler);
  final List<BarSlot> slots;
  final Color color, tint;
  final TextScaler scaler;

  TextPainter _text(String s, TextStyle style, double maxWidth) => TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);

  @override
  void paint(Canvas canvas, Size size) {
    if (slots.isEmpty) return;
    const labelH = 18.0, valueH = 16.0;
    final plotH = size.height - labelH - valueH;
    final top = valueH;
    final maxV = slots.fold<num>(
      0,
      (m, s) => s.value != null && s.value! > m ? s.value! : m,
    );
    final slotW = size.width / slots.length;
    final barW = slotW * 0.56;
    final base = top + plotH;
    canvas.drawLine(
      Offset(0, base),
      Offset(size.width, base),
      Paint()
        ..color = AppColors.border
        ..strokeWidth = 1,
    );
    for (var i = 0; i < slots.length; i++) {
      final s = slots[i];
      final cx = slotW * i + slotW / 2;
      final rect = Rect.fromLTWH(cx - barW / 2, top, barW, plotH);
      if (s.value == null) {
        // No record: dashed outline slot, not a zero bar.
        final p = Paint()
          ..color = AppColors.decorative.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        const dash = 4.0, gap = 3.0;
        final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(rect.left, base - 26, rect.width, 26),
          const Radius.circular(6),
        );
        final path = Path()..addRRect(r);
        for (final m in path.computeMetrics()) {
          for (var d = 0.0; d < m.length; d += dash + gap) {
            canvas.drawPath(m.extractPath(d, d + dash), p);
          }
        }
        final dashLabel = _text(
          '–',
          AppTypography.secondary.copyWith(color: AppColors.decorative),
          slotW,
        );
        dashLabel.paint(
          canvas,
          Offset(cx - dashLabel.width / 2, base - 26 - dashLabel.height - 1),
        );
      } else {
        final h = maxV == 0
            ? 2.0
            : (s.value! / maxV * plotH).clamp(2.0, plotH).toDouble();
        final bar = RRect.fromRectAndCorners(
          Rect.fromLTWH(rect.left, base - h, rect.width, h),
          topLeft: const Radius.circular(7),
          topRight: const Radius.circular(7),
        );
        canvas.drawRRect(bar, Paint()..color = color);
        final v = s.value! == s.value!.roundToDouble()
            ? s.value!.toInt().toString()
            : s.value!.toStringAsFixed(1);
        final vt = _text(
          v,
          AppTypography.caption.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          slotW,
        );
        vt.paint(
          canvas,
          Offset(cx - vt.width / 2, (base - h - vt.height - 2).clamp(0, base)),
        );
      }
      final lt = _text(s.label, AppTypography.caption, slotW);
      lt.paint(canvas, Offset(cx - lt.width / 2, base + 3));
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.slots != slots || old.color != color;
}

class DotPoint {
  const DotPoint({
    required this.minuteOfDay,
    required this.value,
    this.needsReview = false,
  });
  final int minuteOfDay;
  final num value;
  final bool needsReview;
}

/// Sparse measurements as separate dots: no connecting line and no shaded "target" band,
/// so nothing implies values between readings or a clinical range. Hollow dot = flagged for review.
class DotPlot extends StatelessWidget {
  const DotPlot({
    super.key,
    required this.points,
    required this.unit,
    required this.color,
    required this.semanticLabel,
    this.height = 150,
  });

  final List<DotPoint> points;
  final String unit;
  final Color color;
  final String semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: true,
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _DotPainter(
              points,
              color,
              MediaQuery.textScalerOf(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.points, this.color, this.scaler);
  final List<DotPoint> points;
  final Color color;
  final TextScaler scaler;

  TextPainter _t(String s, TextStyle st) => TextPainter(
    text: TextSpan(text: s, style: st),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0, bottom = 20.0, top = 8.0, right = 8.0;
    final plot = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    final minV = points
        .map((p) => p.value)
        .reduce((a, b) => a < b ? a : b)
        .toDouble();
    final maxV = points
        .map((p) => p.value)
        .reduce((a, b) => a > b ? a : b)
        .toDouble();
    final pad = (maxV - minV).abs() < 1e-9
        ? (maxV == 0 ? 1 : maxV * 0.1)
        : (maxV - minV) * 0.25;
    final lo = minV - pad, hi = maxV + pad;
    String f(double v) =>
        (hi - lo) < 10 ? v.toStringAsFixed(1) : v.round().toString();
    for (final frac in [0.0, 1.0]) {
      final y = plot.bottom - plot.height * frac;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final tp = _t(f(lo + (hi - lo) * frac), AppTypography.caption);
      tp.paint(canvas, Offset(left - tp.width - 4, y - tp.height / 2));
    }
    for (final h in [0, 6, 12, 18, 24]) {
      final x = plot.left + plot.width * h / 24;
      final tp = _t(
        h == 24 ? '24' : h.toString().padLeft(2, '0'),
        AppTypography.caption,
      );
      tp.paint(
        canvas,
        Offset(
          (x - tp.width / 2).clamp(0, size.width - tp.width),
          size.height - bottom + 4,
        ),
      );
    }
    for (final p in points) {
      final x = plot.left + plot.width * p.minuteOfDay / 1440;
      final y = plot.bottom - plot.height * ((p.value - lo) / (hi - lo));
      if (p.needsReview) {
        canvas.drawCircle(Offset(x, y), 6, Paint()..color = AppColors.surface);
        canvas.drawCircle(
          Offset(x, y),
          6,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      } else {
        canvas.drawCircle(Offset(x, y), 6, Paint()..color = color);
      }
      final label = _t(
        p.value == p.value.roundToDouble()
            ? p.value.toInt().toString()
            : p.value.toStringAsFixed(1),
        AppTypography.caption.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      );
      label.paint(
        canvas,
        Offset(
          (x - label.width / 2).clamp(plot.left, size.width - label.width),
          y - 9 - label.height,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_DotPainter old) =>
      old.points != points || old.color != color;
}

/// Card wrapper with title, chart, and a one-line "how to read" caption.
class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.icon,
    required this.tint,
    required this.ink,
    required this.title,
    required this.child,
    this.caption,
    this.empty,
  });

  final IconData icon;
  final Color tint, ink;
  final String title;
  final Widget child;
  final String? caption;

  /// When set, the chart is replaced by this honest empty message.
  final String? empty;

  @override
  Widget build(BuildContext context) {
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
              ExcludeSemantics(
                child: Container(
                  height: 30,
                  width: 30,
                  decoration: BoxDecoration(
                    color: tint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 16, color: ink),
                ),
              ),
              const SizedBox(width: AppSpacing.xs + 2),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: AppTypography.title),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (empty != null)
            Text(empty!, style: AppTypography.secondary)
          else
            child,
          if (caption != null && empty == null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(caption!, style: AppTypography.caption),
            ),
        ],
      ),
    );
  }
}
