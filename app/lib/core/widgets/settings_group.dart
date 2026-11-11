import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children, this.title});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      rows.add(children[index]);
      if (index < children.length - 1) {
        rows.add(
          Divider(
            height: 1,
            indent: AppSpacing.md,
            endIndent: AppSpacing.md,
            color: AppColors.border,
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.xs),
            child: Semantics(
              header: true,
              child: Text(title!.toUpperCase(), style: AppTypography.overline),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.cardRadius,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: rows),
        ),
      ],
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.icon,
    this.value,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.destructive = false,
  });

  final String title;
  final IconData? icon;
  final String? value;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? AppColors.errorForeground
        : AppColors.textPrimary;
    // A long value goes under the title so the title keeps one line.
    final stacked =
        value != null && subtitle == null && title.length + value!.length > 28;
    return Semantics(
      button: onTap != null,
      label: [title, ?value, ?subtitle].join('. '),
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 10,
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 20,
                    color: destructive ? color : AppColors.textPrimary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: title.contains(' ') ? 3 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.w500,
                          color: color,
                        ),
                      ),
                      if (subtitle != null)
                        Text(subtitle!, style: AppTypography.caption)
                      else if (stacked)
                        Text(value!, style: AppTypography.caption),
                    ],
                  ),
                ),
                if (value != null && !stacked) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    flex: 0,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: Text(
                        value!,
                        textAlign: TextAlign.end,
                        style: AppTypography.secondary,
                      ),
                    ),
                  ),
                ],
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  trailing!,
                ],
                if (onTap != null && trailing == null) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppColors.decorative,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
