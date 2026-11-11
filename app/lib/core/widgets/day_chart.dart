import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Isi pembacaan untuk hari terpilih (di atas grafik, bukan melayang di atas batang agar jari tidak menutupinya).
class DayReadout {
  const DayReadout({required this.value, required this.label, this.extra});
  final String value, label;
  final String? extra;
}

/// Bingkai gambar yang diberikan ke tiap pelukis grafik.
class DayFrame {
  DayFrame({
    required this.plot,
    required this.count,
    required this.progress,
    required this.selected,
    required this.scaler,
  });
  final Rect plot;
  final int count;

  /// 0..1; sudah memperhitungkan "kurangi gerak" (selalu 1).
  final double progress;
  final int? selected;
  final TextScaler scaler;

  double get slotW => plot.width / count;
  double centerX(int i) => plot.left + slotW * i + slotW / 2;

  /// Tumbuh berurutan dari kiri ke kanan; hasil 0..1 per hari.
  double grow(int i) {
    final delay = count <= 1 ? 0.0 : 0.45 * i / (count - 1);
    return Curves.easeOutCubic.transform(
      ((progress - delay) / 0.55).clamp(0.0, 1.0),
    );
  }

  TextPainter text(String s, TextStyle style, {double? maxWidth}) =>
      TextPainter(
        text: TextSpan(text: s, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: maxWidth ?? double.infinity);

  /// Garis pemandu hari terpilih (hairline) di belakang tanda data.
  void guide(Canvas canvas) {
    final s = selected;
    if (s == null) return;
    canvas.drawLine(
      Offset(centerX(s), plot.top),
      Offset(centerX(s), plot.bottom),
      Paint()
        ..color = AppColors.brand.withValues(alpha: 0.35)
        ..strokeWidth = 1.5,
    );
  }

  void emptySlot(Canvas canvas, int i, {double? y}) {
    final tp = text(
      '–',
      AppTypography.caption.copyWith(color: AppColors.decorative),
    );
    tp.paint(
      canvas,
      Offset(centerX(i) - tp.width / 2, (y ?? plot.bottom) - tp.height - 2),
    );
  }
}

abstract class DayPainter {
  const DayPainter();
  void paint(Canvas canvas, DayFrame f);
}

/// Grafik harian yang bisa disentuh/digeser. Satu pembacaan di atas grafik, kolom sumbu-x dan label
/// semantik per hari (TalkBack). Animasi tumbuh mati bila pengguna memilih "kurangi gerak".
class DayChart extends StatefulWidget {
  const DayChart({
    super.key,
    required this.count,
    required this.painter,
    required this.dataKey,
    required this.readout,
    required this.semanticFor,
    required this.xLabel,
    required this.summary,
    this.hint = 'Geser atau ketuk untuk melihat tiap hari',
    this.height = 150,
    this.leftInset = 0,
    this.accent,
    this.dimmed = false,
  });

  final int count;
  final DayPainter painter;

  /// Berubah bila datanya berubah → animasi diputar ulang dan pilihan dihapus.
  final Object dataKey;
  final DayReadout? Function(int i) readout;
  final String Function(int i) semanticFor;
  final String? Function(int i) xLabel;
  final String summary, hint;
  final double height, leftInset;
  final Color? accent;

  /// Data lama masih tampil saat data baru dimuat.
  final bool dimmed;

  @override
  State<DayChart> createState() => _DayChartState();
}

class _DayChartState extends State<DayChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  int? selected;
  bool reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final r = MediaQuery.disableAnimationsOf(context);
    final first = !controller.isAnimating && controller.value == 0;
    reduced = r;
    if (r) {
      controller.value = 1;
    } else if (first) {
      controller.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(DayChart old) {
    super.didUpdateWidget(old);
    if (old.dataKey != widget.dataKey) {
      selected = null;
      if (reduced) {
        controller.value = 1;
      } else {
        controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void pick(double dx, double width, {bool toggle = false}) {
    final plotW = width - widget.leftInset;
    final i = ((dx - widget.leftInset) / (plotW / widget.count)).floor().clamp(
      0,
      widget.count - 1,
    );
    if (toggle && selected == i) {
      setState(() => selected = null);
      return;
    }
    if (i != selected) {
      HapticFeedback.selectionClick();
      setState(() => selected = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = selected == null ? null : widget.readout(selected!);
    final scaler = MediaQuery.textScalerOf(context);
    return Opacity(
      opacity: widget.dimmed ? 0.5 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pembacaan: nilai besar, label kecil; menggantikan teks petunjuk tanpa mengubah tinggi.
          AnimatedSwitcher(
            duration: reduced
                ? Duration.zero
                : const Duration(milliseconds: 150),
            child: SizedBox(
              key: ValueKey(selected),
              height: 76 * math.max(1.0, scaler.scale(1)),
              width: double.infinity,
              child: r == null
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Text(widget.hint, style: AppTypography.caption),
                    )
                  : Semantics(
                      liveRegion: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            r.value,
                            style: AppTypography.title.copyWith(
                              color: widget.accent ?? AppColors.brand,
                            ),
                          ),
                          Text(
                            r.extra == null
                                ? r.label
                                : '${r.label} · ${r.extra}',
                            style: AppTypography.caption,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          LayoutBuilder(
            builder: (context, c) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) =>
                  pick(d.localPosition.dx, c.maxWidth, toggle: true),
              onHorizontalDragStart: (d) =>
                  pick(d.localPosition.dx, c.maxWidth),
              onHorizontalDragUpdate: (d) =>
                  pick(d.localPosition.dx, c.maxWidth),
              child: Semantics(
                container: true,
                label: widget.summary,
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) => CustomPaint(
                    size: Size(c.maxWidth, widget.height),
                    painter: _Painter(
                      widget,
                      controller.value,
                      selected,
                      scaler,
                      (i) => setState(() => selected = i),
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

class _Painter extends CustomPainter {
  _Painter(this.w, this.progress, this.selected, this.scaler, this.onSelect);
  final void Function(int i) onSelect;
  final DayChart w;
  final double progress;
  final int? selected;
  final TextScaler scaler;

  @override
  void paint(Canvas canvas, Size size) {
    const bottom = 22.0;
    final plot = Rect.fromLTRB(
      w.leftInset,
      4,
      size.width,
      size.height - bottom,
    );
    final f = DayFrame(
      plot: plot,
      count: w.count,
      progress: progress,
      selected: selected,
      scaler: scaler,
    );
    w.painter.paint(canvas, f);
    // Sumbu-x: jarang agar tidak bertabrakan; hari terpilih selalu berlabel.
    final every = (w.count / 7).ceil();
    for (var i = 0; i < w.count; i++) {
      if (i % every != 0 && i != selected && i != w.count - 1) continue;
      if (i != selected &&
          i != w.count - 1 &&
          w.count - 1 - i < every ~/ 2 + 1) {
        continue;
      }
      final s = w.xLabel(i);
      if (s == null) continue;
      final tp = f.text(
        s,
        AppTypography.caption.copyWith(
          color: i == selected
              ? AppColors.textPrimary
              : AppColors.textSecondary,
          fontWeight: i == selected ? FontWeight.w700 : FontWeight.w400,
        ),
      );
      tp.paint(
        canvas,
        Offset(
          (f.centerX(i) - tp.width / 2).clamp(0.0, size.width - tp.width),
          plot.bottom + 4,
        ),
      );
    }
  }

  /// Satu simpul semantik per hari: TalkBack membaca nilai tiap hari dan ketuk dua kali memilihnya.
  @override
  SemanticsBuilderCallback? get semanticsBuilder => (size) {
    final plotW = size.width - w.leftInset;
    final cell = plotW / w.count;
    return [
      for (var i = 0; i < w.count; i++)
        CustomPainterSemantics(
          rect: Rect.fromLTWH(w.leftInset + cell * i, 0, cell, size.height),
          properties: SemanticsProperties(
            label: w.semanticFor(i),
            textDirection: TextDirection.ltr,
            button: true,
            onTap: () => onSelect(i),
          ),
        ),
    ];
  };

  @override
  bool shouldRebuildSemantics(_Painter old) => old.w.dataKey != w.dataKey;

  @override
  bool shouldRepaint(_Painter old) =>
      old.progress != progress ||
      old.selected != selected ||
      old.w.dataKey != w.dataKey;
}
