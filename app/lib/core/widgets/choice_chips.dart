import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

class PillChip extends StatelessWidget {
  const PillChip({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected ? AppColors.primary : AppColors.surface,
        shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.primary : AppColors.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[const Icon(Icons.check, size: 18, color: AppColors.onPrimary), const SizedBox(width: 6)],
                  Flexible(
                    child: Text(
                      label,
                      style: AppTypography.secondaryStrong.copyWith(color: selected ? AppColors.onPrimary : AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SegmentedPills<T> extends StatelessWidget {
  const SegmentedPills({super.key, required this.options, required this.value, required this.onChanged});

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.input)),
      child: Row(
        children: [
          for (final (optionValue, label) in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: optionValue == value,
                label: label,
                excludeSemantics: true,
                onTap: () => onChanged(optionValue),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(optionValue),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: optionValue == value ? AppColors.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.input - 4),
                      boxShadow: optionValue == value ? AppShadows.soft : null,
                    ),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: optionValue == value ? AppTypography.secondaryStrong : AppTypography.secondary,
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
