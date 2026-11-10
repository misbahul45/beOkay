import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class EditorialPhoto extends StatelessWidget {
  const EditorialPhoto({
    super.key,
    this.figureX = 0.66,
    this.tone = 0,
    this.radius = 0,
    this.child,
  });

  final double figureX;
  final int tone;
  final double radius;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CustomPaint(
        painter: _EditorialPhotoPainter(figureX: figureX, tone: tone),
        child: child ?? const SizedBox.expand(),
      ),
    );
  }
}

class _EditorialPhotoPainter extends CustomPainter {
  _EditorialPhotoPainter({required this.figureX, required this.tone});

  final double figureX;
  final int tone;

  static const _bases = [
    [Color(0xFF4A5560), Color(0xFF12161A)],
    [Color(0xFF5E6C77), Color(0xFF171C21)],
    [Color(0xFF3C464F), Color(0xFF0E1215)],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;
    final base = _bases[tone % _bases.length];

    canvas.drawRect(
      rect,
      Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(w, h), base),
    );

    final lightCenter = Offset(w * figureX, h * 0.12);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(lightCenter, w * 0.75, [
          const Color(0x7ADCE7F0),
          const Color(0x00DCE7F0),
        ]),
    );

    for (final (startX, endX, alpha) in [
      (0.06, 0.62, 0x1F),
      (0.36, 0.7, 0x14),
    ]) {
      final path = Path()
        ..moveTo(w * startX, 0)
        ..lineTo(w * (startX + 0.18), 0)
        ..lineTo(w * endX, h)
        ..lineTo(w * (endX - 0.22), h)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(w * startX, 0),
            Offset(w * endX, h),
            [
              Color.fromARGB(0, 200, 217, 232),
              Color.fromARGB(alpha, 200, 217, 232),
            ],
          ),
      );
    }

    final unit = h < w * 1.2 ? h * 0.9 : w;
    final headWidth = unit * 0.2;
    final headHeight = headWidth * 1.22;
    final centerX = w * figureX;
    final headTop = h * 0.16;
    final blur = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6);

    final shoulderWidth = unit * 0.8;
    final shouldersTop = headTop + headHeight * 1.18;
    final shoulderHeight = h - shouldersTop + 4;
    final shoulders = Path()
      ..moveTo(centerX - shoulderWidth / 2, h + 4)
      ..lineTo(centerX - shoulderWidth / 2, shouldersTop + shoulderHeight * 0.5)
      ..cubicTo(
        centerX - shoulderWidth * 0.5,
        shouldersTop + shoulderHeight * 0.2,
        centerX - shoulderWidth * 0.34,
        shouldersTop + shoulderHeight * 0.06,
        centerX - shoulderWidth * 0.16,
        shouldersTop,
      )
      ..lineTo(centerX + shoulderWidth * 0.16, shouldersTop)
      ..cubicTo(
        centerX + shoulderWidth * 0.34,
        shouldersTop + shoulderHeight * 0.06,
        centerX + shoulderWidth * 0.5,
        shouldersTop + shoulderHeight * 0.2,
        centerX + shoulderWidth / 2,
        shouldersTop + shoulderHeight * 0.5,
      )
      ..lineTo(centerX + shoulderWidth / 2, h + 4)
      ..close();
    canvas.drawPath(
      shoulders,
      blur
        ..shader = ui.Gradient.linear(Offset(0, shouldersTop), Offset(0, h), [
          const Color(0xFF323A42),
          const Color(0xFF090B0D),
        ]),
    );

    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(centerX, headTop + headHeight * 1.05),
        width: headWidth * 0.38,
        height: headHeight * 0.4,
      ),
      Paint()
        ..color = const Color(0xFF0B0E11)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX, headTop + headHeight / 2),
        width: headWidth,
        height: headHeight,
      ),
      Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6)
        ..shader = ui.Gradient.linear(
          Offset(centerX - headWidth / 2, headTop),
          Offset(centerX + headWidth / 2, headTop + headHeight),
          [const Color(0xFF303840), const Color(0xFF0B0E11)],
        ),
    );

    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.3, w, h * 0.7),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, h * 0.3), Offset(0, h), [
          const Color(0x00171B20),
          const Color(0xF0171B20),
        ]),
    );
  }

  @override
  bool shouldRepaint(_EditorialPhotoPainter old) =>
      old.figureX != figureX || old.tone != tone;
}
