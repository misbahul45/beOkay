import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/domain_style.dart';

Future<void> showQuickRecord(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.background,
      builder: (sheet) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          0,
          AppSpacing.page,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Apa yang ingin kamu catat?',
                style: AppTypography.heading,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _Option(
              style: DomainStyle.meal,
              subtitle: 'Makanan dan porsi',
              sheet: sheet,
              outer: context,
            ),
            const SizedBox(height: AppSpacing.xs),
            _Option(
              style: DomainStyle.glucose,
              subtitle: 'Hasil glukometer dan konteksnya',
              sheet: sheet,
              outer: context,
            ),
            const SizedBox(height: AppSpacing.xs),
            _Option(
              style: DomainStyle.activity,
              subtitle: 'Sesi, durasi, dan intensitas',
              sheet: sheet,
              outer: context,
            ),
            const SizedBox(height: AppSpacing.xs),
            _Option(
              style: DomainStyle.medication,
              subtitle: 'Konfirmasi obat dan jadwalnya',
              sheet: sheet,
              outer: context,
              route: Routes.medications,
            ),
          ],
        ),
      ),
    );

class _Option extends StatelessWidget {
  const _Option({
    required this.style,
    required this.subtitle,
    required this.sheet,
    required this.outer,
    this.route,
  });

  final DomainStyle style;
  final String subtitle;
  final BuildContext sheet;
  final BuildContext outer;
  final String? route;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Catat ${style.label}. $subtitle',
    excludeSemantics: true,
    onTap: () => _go(),
    child: Material(
      color: AppColors.surface,
      borderRadius: AppRadius.cardRadius,
      child: InkWell(
        borderRadius: AppRadius.cardRadius,
        onTap: _go,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: style.tint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(style.icon, color: style.ink),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(style.label, style: AppTypography.bodyStrong),
                      Text(subtitle, style: AppTypography.secondary),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: AppColors.decorative),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  void _go() {
    Navigator.pop(sheet);
    outer.push(route ?? style.addRoute);
  }
}
