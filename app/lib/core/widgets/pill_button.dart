import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

enum PillButtonKind { primary, ink, secondary, ghost, danger, light }

class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = PillButtonKind.primary,
    this.icon,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final PillButtonKind kind;
  final IconData? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, side) = switch (kind) {
      PillButtonKind.primary => (
        AppColors.primary,
        AppColors.onPrimary,
        BorderSide.none,
      ),
      PillButtonKind.ink => (
        AppColors.textPrimary,
        AppColors.surface,
        BorderSide.none,
      ),
      PillButtonKind.secondary => (
        AppColors.surface,
        AppColors.textPrimary,
        BorderSide(color: AppColors.border),
      ),
      PillButtonKind.ghost => (
        Colors.transparent,
        AppColors.textPrimary,
        BorderSide.none,
      ),
      PillButtonKind.danger => (
        AppColors.errorBackground,
        AppColors.errorForeground,
        BorderSide.none,
      ),
      PillButtonKind.light => (
        AppColors.surface,
        AppColors.textPrimary,
        BorderSide.none,
      ),
    };
    final enabled = onPressed != null && !loading;
    final content = loading
        ? SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: foreground,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: foreground),
                const SizedBox(width: AppSpacing.xs),
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyStrong.copyWith(color: foreground),
                ),
              ),
            ],
          );
    final button = FilledButton(
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        disabledBackgroundColor:
            kind == PillButtonKind.primary || kind == PillButtonKind.ink
            ? AppColors.disabled
            : background.withValues(alpha: 0.6),
        disabledForegroundColor:
            kind == PillButtonKind.primary || kind == PillButtonKind.ink
            ? AppColors.onPrimary
            : AppColors.decorative,
        minimumSize: const Size(
          AppSpacing.minTouchTarget,
          AppSpacing.buttonHeight,
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md + 4),
        shape: const StadiumBorder(),
        side: side,
        elevation: 0,
      ),
      child: content,
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: loading ? '$label, sedang diproses' : label,
      excludeSemantics: true,
      onTap: enabled ? onPressed : null,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}
