import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/domain_style.dart';

Future<void> showQuickRecord(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: AppColors.background,
  builder: (sheet) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.lg),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text('Apa yang ingin kamu catat?', style: AppTypography.heading)),
        const SizedBox(height: AppSpacing.md),
        _Option(style: DomainStyle.meal, subtitle: 'Makanan, porsi, dan catatanmu', sheet: sheet, outer: context),
        const SizedBox(height: AppSpacing.xs),
        _Option(style: DomainStyle.glucose, subtitle: 'Hasil glukometer dan konteks pengukuran', sheet: sheet, outer: context),
        const SizedBox(height: AppSpacing.xs),
        _Option(style: DomainStyle.activity, subtitle: 'Sesi, durasi, dan intensitas yang kamu rasakan', sheet: sheet, outer: context),
        const SizedBox(height: AppSpacing.xs),
        const _Disabled(icon: Icons.medication_outlined, title: 'Konsumsi obat', subtitle: 'Belum tersedia di versi ini'),
      ],
    ),
  ),
);

class _Option extends StatelessWidget {
  const _Option({required this.style, required this.subtitle, required this.sheet, required this.outer});

  final DomainStyle style;
  final String subtitle;
  final BuildContext sheet;
  final BuildContext outer;

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
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Row(
              children: [
                Container(
                  height: 44,
                  width: 44,
                  decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                  child: Icon(style.icon, color: AppColors.primary),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Text(style.label, style: AppTypography.bodyStrong), Text(subtitle, style: AppTypography.secondary)],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.decorative),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  void _go() {
    Navigator.pop(sheet);
    outer.push(style.addRoute);
  }
}

class _Disabled extends StatelessWidget {
  const _Disabled({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$title. $subtitle',
    excludeSemantics: true,
    child: Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: AppRadius.cardRadius),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.decorative),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(title, style: AppTypography.bodyStrong.copyWith(color: AppColors.textSecondary)), Text(subtitle, style: AppTypography.secondary)],
            ),
          ),
        ],
      ),
    ),
  );
}
