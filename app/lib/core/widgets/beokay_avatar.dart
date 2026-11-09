import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// beOkay's identity avatar: the logo mark in a soft ring. It bobs gently unless the
/// user asked for reduced motion (system setting or the app preference).
class BeOkayAvatar extends StatefulWidget {
  const BeOkayAvatar({super.key, this.size = 56, this.animate = true});

  final double size;
  final bool animate;

  @override
  State<BeOkayAvatar> createState() => _BeOkayAvatarState();
}

class _BeOkayAvatarState extends State<BeOkayAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = !widget.animate || MediaQuery.maybeDisableAnimationsOf(context) == true;
    if (still) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_controller.value);
          return Transform.translate(offset: Offset(0, -size * 0.04 * math.sin(t * math.pi)), child: child);
        },
        child: Container(
          height: size,
          width: size,
          padding: EdgeInsets.all(size * 0.12),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.surface,
            border: Border.all(color: AppColors.aqua.withValues(alpha: 0.55), width: size * 0.03),
            boxShadow: [BoxShadow(color: AppColors.brand.withValues(alpha: 0.14), blurRadius: size * 0.3, offset: Offset(0, size * 0.1))],
          ),
          child: Image.asset('assets/images/logo_mark.png', fit: BoxFit.contain, filterQuality: FilterQuality.medium),
        ),
      ),
    );
  }
}

/// Speech bubble with a small tail towards the avatar on the left.
class AvatarBubble extends StatelessWidget {
  const AvatarBubble({super.key, required this.title, this.detail, this.dark = false});

  final String title;
  final String? detail;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final bg = dark ? Colors.white.withValues(alpha: 0.14) : AppColors.surface;
    final fg = dark ? AppColors.onPrimary : AppColors.textPrimary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CustomPaint(size: const Size(8, 14), painter: _TailPainter(bg)),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2, vertical: AppSpacing.sm),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.input + 2)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(liveRegion: true, child: Text(title, style: AppTypography.bodyStrong.copyWith(color: fg))),
                if (detail != null) Text(detail!, style: AppTypography.secondary.copyWith(color: dark ? const Color(0xFFD3EAE6) : AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TailPainter extends CustomPainter {
  _TailPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(0, size.height / 2)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TailPainter old) => old.color != color;
}

/// Avatar with its message, used on Beranda and onboarding.
class AvatarGreeting extends StatelessWidget {
  const AvatarGreeting({super.key, required this.message, this.size = 52, this.dark = false});

  final ({String title, String? detail}) message;
  final double size;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        BeOkayAvatar(size: size),
        const SizedBox(width: 4),
        Expanded(child: AvatarBubble(title: message.title, detail: message.detail, dark: dark)),
      ],
    );
  }
}

/// Loading state: avatar plus three quiet dots. Static when motion is reduced.
class AvatarLoader extends StatefulWidget {
  const AvatarLoader({super.key, this.label = 'Memuat'});
  final String label;

  @override
  State<AvatarLoader> createState() => _AvatarLoaderState();
}

class _AvatarLoaderState extends State<AvatarLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BeOkayAvatar(size: 88),
          const SizedBox(height: AppSpacing.md),
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: 7,
                    width: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.brand.withValues(alpha: 0.25 + 0.75 * (0.5 + 0.5 * math.sin((_c.value * 2 - i * 0.35) * math.pi)).clamp(0.0, 1.0)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
