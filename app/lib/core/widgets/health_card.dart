import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class HealthCard extends StatelessWidget {
  const HealthCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    borderRadius: AppRadius.cardRadius,
    child: SizedBox(
      width: double.infinity,
      child: Padding(padding: const EdgeInsets.all(AppSpacing.md), child: child),
    ),
  );
}
