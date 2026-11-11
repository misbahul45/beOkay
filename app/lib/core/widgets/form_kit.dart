import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'domain_style.dart';

class FormHero extends StatelessWidget {
  const FormHero({
    super.key,
    required this.icon,
    required this.tint,
    required this.ink,
    required this.title,
    this.subtitle,
  });

  factory FormHero.domain(DomainStyle s, String title, {String? subtitle}) =>
      FormHero(
        icon: s.icon,
        tint: s.tint,
        ink: s.ink,
        title: title,
        subtitle: subtitle,
      );

  final IconData icon;
  final Color tint, ink;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
    padding: const EdgeInsets.all(AppSpacing.cardPadding),
    decoration: BoxDecoration(color: tint, borderRadius: AppRadius.cardRadius),
    child: Row(
      children: [
        Container(
          height: 40,
          width: 40,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: ink, size: 20),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.bodyStrong),
              if (subtitle != null)
                Text(subtitle!, style: AppTypography.caption),
            ],
          ),
        ),
      ],
    ),
  );
}

class FormSection extends StatelessWidget {
  const FormSection({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Material(
      color: AppColors.surface,
      borderRadius: AppRadius.cardRadius,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.cardPadding,
          AppSpacing.sm,
          AppSpacing.cardPadding,
          AppSpacing.cardPadding,
        ),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title.toUpperCase(), style: AppTypography.overline),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: AppTypography.caption),
              ],
              const SizedBox(height: AppSpacing.xs),
              ...children,
            ],
          ),
        ),
      ),
    ),
  );
}

class DateTimeTile extends StatelessWidget {
  const DateTimeTile({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.showTime = true,
    this.detail,
  });

  final String label;
  final DateTime value;
  final VoidCallback? onTap;
  final bool showTime;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('EEEE, d MMM y', 'id_ID').format(value);
    final time = DateFormat('HH.mm', 'id_ID').format(value);
    final second = [if (showTime) time, ?detail].join(' · ');
    return Semantics(
      button: onTap != null,
      label: '$label: $date${showTime ? ', pukul $time' : ''}',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                Icon(
                  Icons.event_outlined,
                  color: onTap == null ? AppColors.disabled : AppColors.brand,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: AppTypography.caption),
                      Text(date, style: AppTypography.bodyStrong),
                      if (second.isNotEmpty)
                        Text(second, style: AppTypography.secondary),
                    ],
                  ),
                ),
                if (onTap != null)
                  Text(
                    'Ubah',
                    style: AppTypography.secondaryStrong.copyWith(
                      color: AppColors.brand,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FormNote extends StatelessWidget {
  const FormNote(this.text, {super.key, this.icon = Icons.info_outline});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: AppTypography.caption)),
      ],
    ),
  );
}

class SaveBar extends StatelessWidget {
  const SaveBar({super.key, required this.button, this.note});

  final Widget button;
  final String? note;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      button,
      if (note != null) ...[
        const SizedBox(height: 4),
        Text(note!, style: AppTypography.caption, textAlign: TextAlign.center),
      ],
    ],
  );
}
