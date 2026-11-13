import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum SparkState {
  idle,
  listening,
  thinking,
  searching,
  responding,
  encouraging,
  celebrating,

  neutral,

  error,

  paused,

  awaitingConfirmation,

  safetyWarning,
}

SparkState sparkStateFromWire(String? wire) => switch (wire) {
  'THINKING' => SparkState.thinking,
  'ENCOURAGING' => SparkState.encouraging,
  'CELEBRATING' => SparkState.celebrating,
  'AWAITING_CONFIRMATION' => SparkState.awaitingConfirmation,
  'SAFETY_WARNING' => SparkState.safetyWarning,
  _ => SparkState.neutral,
};

class BeOkaySpark extends StatefulWidget {
  const BeOkaySpark({
    super.key,
    this.size = 56,
    this.state = SparkState.idle,
    this.semanticLabel,
  });

  final double size;
  final SparkState state;

  final String? semanticLabel;

  static const double faceMinSize = 40;

  @override
  State<BeOkaySpark> createState() => _BeOkaySparkState();
}

class _BeOkaySparkState extends State<BeOkaySpark>
    with TickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  bool _still = false;

  bool get _moves =>
      !_still &&
      widget.state != SparkState.error &&
      widget.state != SparkState.paused &&
      widget.state != SparkState.safetyWarning;

  static const ambientCycles = 3;

  bool get _busy =>
      widget.state == SparkState.thinking ||
      widget.state == SparkState.searching;

  void _sync({bool restart = false}) {
    if (!_moves) {
      _loop.stop();
      _loop.value = 0;
      return;
    }
    if (_busy) {
      if (!_loop.isAnimating || restart) _loop.repeat();
    } else if (restart || (!_loop.isAnimating && _loop.value == 0)) {
      _loop.value = 0;
      _loop.repeat(count: ambientCycles);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) == true;
    _sync();
  }

  @override
  void didUpdateWidget(BeOkaySpark old) {
    super.didUpdateWidget(old);
    if (widget.state == SparkState.celebrating &&
        old.state != SparkState.celebrating &&
        !_still) {
      _burst.forward(from: 0);
    }
    _sync(restart: old.state != widget.state);
  }

  @override
  void initState() {
    super.initState();
    if (widget.state == SparkState.celebrating) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_still) _burst.forward(from: 0);
      });
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final painter = RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: Listenable.merge([_loop, _burst]),
          builder: (context, _) => CustomPaint(
            painter: SparkPainter(
              state: widget.state,
              t: _moves ? _loop.value : 0,
              burst: _still
                  ? (widget.state == SparkState.celebrating ? 0.6 : 0)
                  : _burst.value,
              showFace: widget.size >= BeOkaySpark.faceMinSize,
            ),
          ),
        ),
      ),
    );
    final label = widget.semanticLabel;
    return label == null
        ? ExcludeSemantics(child: painter)
        : Semantics(label: label, image: true, child: painter);
  }
}

class SparkPainter extends CustomPainter {
  SparkPainter({
    required this.state,
    required this.t,
    this.burst = 0,
    this.showFace = true,
  });

  final SparkState state;

  final double t;

  final double burst;
  final bool showFace;

  static final Path _outer = Path()
    ..moveTo(50, 6)
    ..cubicTo(54, 22, 78, 34, 80, 60)
    ..cubicTo(82, 80, 68, 94, 50, 94)
    ..cubicTo(32, 94, 18, 80, 20, 60)
    ..cubicTo(21, 46, 30, 40, 36, 28)
    ..cubicTo(38, 36, 42, 40, 46, 38)
    ..cubicTo(44, 26, 46, 14, 50, 6)
    ..close();
  static final Path _mid = Path()
    ..moveTo(50, 22)
    ..cubicTo(54, 33, 72, 43, 73, 62)
    ..cubicTo(74, 78, 63, 90, 50, 90)
    ..cubicTo(37, 90, 26, 78, 27, 62)
    ..cubicTo(28, 51, 36, 47, 42, 41)
    ..cubicTo(44, 46, 47, 47, 49, 43)
    ..cubicTo(48, 35, 48, 28, 50, 22)
    ..close();
  static final Path _inner = Path()
    ..moveTo(50, 50)
    ..cubicTo(55, 58, 63, 63, 63, 73)
    ..cubicTo(63, 82, 57, 87, 50, 87)
    ..cubicTo(43, 87, 37, 82, 37, 73)
    ..cubicTo(37, 64, 45, 60, 50, 50)
    ..close();

  double get _wave => math.sin(t * 2 * math.pi);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    canvas.save();
    canvas.scale(s);

    final dim = state == SparkState.error;
    final glow =
        state == SparkState.listening || state == SparkState.celebrating;
    if (glow) {
      canvas.drawCircle(
        const Offset(50, 52),
        48,
        Paint()..color = AppColors.cream,
      );
    }

    final calm =
        state == SparkState.thinking ||
        state == SparkState.neutral ||
        state == SparkState.awaitingConfirmation;
    var sway = (calm ? 0.6 : 2.0) * math.pi / 180 * _wave;
    var stretch = 1 + (calm ? 0.01 : 0.02) * _wave;
    var lift = 0.0;
    switch (state) {
      case SparkState.listening:
        sway += 4 * math.pi / 180;
      case SparkState.responding:
        lift = -3 * (0.5 + 0.5 * _wave).abs();
      case SparkState.encouraging:
        stretch = 1.03 + 0.03 * (0.5 + 0.5 * _wave);
      case SparkState.error:
      case SparkState.paused:
      case SparkState.safetyWarning:
        sway = 0;
        stretch = 1;
      default:
        break;
    }

    canvas.save();
    canvas.translate(50, 94 + lift);
    canvas.rotate(sway);
    canvas.scale(1, stretch);
    canvas.translate(-50, -94);
    canvas.drawPath(
      _outer,
      Paint()..color = dim ? const Color(0xFFE9A594) : AppColors.sparkCoral,
    );
    canvas.drawPath(
      _mid,
      Paint()..color = dim ? const Color(0xFFF3C985) : AppColors.sparkAmber,
    );
    canvas.drawPath(_inner, Paint()..color = AppColors.sparkCore);
    if (showFace) _face(canvas);
    canvas.restore();

    _extras(canvas);
    canvas.restore();
  }

  void _face(Canvas canvas) {
    final eye = Paint()..color = AppColors.sparkEye;
    var ex = 0.0, ey = 0.0;
    if (state == SparkState.thinking) ey = -2.2;
    if (state == SparkState.searching) ex = 1.8 * _wave;
    final eh = state == SparkState.celebrating ? 3.0 : 5.2;
    for (final cx in const [45.2, 54.8]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + ex, 72 + ey),
          width: 3.8,
          height: eh,
        ),
        eye,
      );
    }
    final stroke = Paint()
      ..color = AppColors.sparkEye
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    switch (state) {
      case SparkState.neutral:
      case SparkState.error:
      case SparkState.thinking:
      case SparkState.safetyWarning:
        canvas.drawLine(const Offset(47, 79.5), const Offset(53, 79.5), stroke);
      case SparkState.responding:
      case SparkState.celebrating:
        canvas.drawPath(
          Path()
            ..moveTo(46, 78)
            ..quadraticBezierTo(50, 84, 54, 78)
            ..close(),
          eye,
        );
      default:
        canvas.drawPath(
          Path()
            ..moveTo(46.5, 78.5)
            ..quadraticBezierTo(50, 82.5, 53.5, 78.5),
          stroke,
        );
    }
  }

  void _badge(Canvas canvas, Color color, String glyph) {
    const center = Offset(80, 84);
    canvas.drawCircle(center, 13, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawCircle(center, 10.5, Paint()..color = color);
    final mark = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    if (glyph == '!') {
      canvas.drawLine(const Offset(80, 78), const Offset(80, 85.5), mark);
      canvas.drawCircle(
        const Offset(80, 90),
        1.6,
        Paint()..color = const Color(0xFFFFFFFF),
      );
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(76.5, 80.5)
          ..quadraticBezierTo(76.5, 76.5, 80, 76.5)
          ..quadraticBezierTo(83.5, 76.5, 83.5, 80)
          ..quadraticBezierTo(83.5, 82.5, 80, 84)
          ..lineTo(80, 85.5),
        mark,
      );
      canvas.drawCircle(
        const Offset(80, 90),
        1.6,
        Paint()..color = const Color(0xFFFFFFFF),
      );
    }
  }

  void _extras(Canvas canvas) {
    if (state == SparkState.awaitingConfirmation) {
      _badge(canvas, AppColors.brand, '?');
    }
    if (state == SparkState.safetyWarning) {
      _badge(canvas, const Color(0xFF3E5560), '!');
    }
    if (state == SparkState.thinking) {
      final ember = Paint()..color = AppColors.sparkAmber;
      const base = [(70.0, 20.0, 3.2), (78.0, 12.0, 2.4), (84.0, 6.0, 1.6)];
      for (var i = 0; i < base.length; i++) {
        final (x, y, r) = base[i];
        final rise = ((t + i / 3) % 1) * 6;
        ember.color = AppColors.sparkAmber.withValues(
          alpha: 1 - ((t + i / 3) % 1) * 0.6,
        );
        canvas.drawCircle(Offset(x, y - rise + 3), r, ember);
      }
    }
    if (state == SparkState.searching) {
      final active = (t * 3).floor() % 3;
      const dots = [Offset(86, 44), Offset(90, 56), Offset(88, 68)];
      for (var i = 0; i < dots.length; i++) {
        canvas.drawCircle(
          dots[i],
          2.6,
          Paint()
            ..color = AppColors.brand.withValues(alpha: i == active ? 1 : 0.35),
        );
      }
    }
    if (state == SparkState.celebrating && burst > 0 && burst < 1) {
      final grow = Curves.easeOut.transform(burst);
      final fade = 1 - Curves.easeIn.transform(burst);
      final paint = Paint()
        ..color = AppColors.sparkAmber.withValues(alpha: fade);
      const stars = [
        (14.0, 20.0, 4.0),
        (86.0, 18.0, 5.0),
        (8.0, 52.0, 3.0),
        (93.0, 50.0, 3.4),
        (26.0, 6.0, 3.0),
        (72.0, 4.0, 2.6),
      ];
      for (final (x, y, r) in stars) {
        _star(canvas, Offset(x, y - 4 * grow), r * (0.6 + 0.6 * grow), paint);
      }
    }
  }

  void _star(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4 - math.pi / 2;
      final rr = i.isEven ? r : r * 0.4;
      final p = c + Offset(math.cos(a) * rr, math.sin(a) * rr);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), paint);
  }

  @override
  bool shouldRepaint(SparkPainter old) =>
      old.state != state ||
      old.t != t ||
      old.burst != burst ||
      old.showFace != showFace;
}
