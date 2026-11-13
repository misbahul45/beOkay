import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.shadow = true,
  });

  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final bool shadow;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: color ?? AppColors.surface,
      borderRadius: AppRadius.cardRadius,
      boxShadow: shadow ? AppShadows.soft : null,
    ),
    child: Material(
      type: MaterialType.transparency,
      borderRadius: AppRadius.cardRadius,
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class Overline extends StatelessWidget {
  const Overline(this.text, {super.key, this.color, this.header = true});

  final String text;
  final Color? color;
  final bool header;

  @override
  Widget build(BuildContext context) => Semantics(
    header: header,
    child: Text(
      text,
      style: AppTypography.overline.copyWith(
        color: color ?? AppColors.textSecondary,
      ),
    ),
  );
}
