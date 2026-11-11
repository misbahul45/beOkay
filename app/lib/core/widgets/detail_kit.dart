import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'domain_style.dart';

String friendlyStamp(String? iso) {
  if (iso == null || iso.isEmpty) return '–';
  final t = DateTime.tryParse(iso);
  if (t == null) return iso;
  return DateFormat('d MMM y · HH.mm', 'id_ID').format(t.toLocal());
}

class DetailHero extends StatelessWidget {
  const DetailHero({
    super.key,
    required this.style,
    required this.eyebrow,
    required this.value,
    this.unit,
    this.chips = const [],
    this.archived = false,
  });

  final DomainStyle style;
  final String eyebrow, value;
  final String? unit;
  final List<String> chips;
  final bool archived;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: archived ? AppColors.surfaceMuted : style.tint,
      borderRadius: BorderRadius.circular(AppRadius.hero),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(style.icon, color: style.ink, size: 20),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow,
                    style: AppTypography.secondaryStrong.copyWith(
                      color: style.ink,
                    ),
                  ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 6,
                    children: [
                      Text(value, style: AppTypography.metricLarge),
                      if (unit != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(unit!, style: AppTypography.secondary),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (chips.isNotEmpty || archived) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (archived) _Chip('Diarsipkan', ink: AppColors.errorForeground),
              for (final c in chips) _Chip(c, ink: style.ink),
            ],
          ),
        ],
      ],
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {required this.ink});

  final String text;
  final Color ink;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: AppRadius.pillRadius,
    ),
    child: Text(
      text,
      style: AppTypography.caption.copyWith(
        color: ink,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class DetailSection extends StatelessWidget {
  const DetailSection({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
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
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title.toUpperCase(),
                        style: AppTypography.overline,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              ...children,
            ],
          ),
        ),
      ),
    ),
  );
}

class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value, {super.key});

  final String label, value;

  @override
  Widget build(BuildContext context) {
    final scaled = MediaQuery.textScalerOf(context).scale(14) > 18;
    final long = scaled || label.length + value.length > 34;
    final valueText = Text(
      value,
      style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
      textAlign: long ? TextAlign.start : TextAlign.end,
    );
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: long
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTypography.secondary),
                  valueText,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTypography.secondary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: valueText),
                ],
              ),
      ),
    );
  }
}

class RevisionEntry {
  const RevisionEntry({
    required this.version,
    required this.reason,
    required this.createdAt,
    this.before,
  });

  final int version;
  final String reason;
  final String createdAt;
  final String? before;
}

class RevisionTimeline extends StatelessWidget {
  const RevisionTimeline({super.key, required this.entries});

  final List<RevisionEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Text(
        'Belum ada koreksi. Setiap koreksi menyimpan versi sebelumnya.',
        style: AppTypography.secondary,
      );
    }
    return Column(
      children: [
        for (final e in entries)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(left: 44, bottom: 8),
              leading: Container(
                width: 34,
                height: 26,
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  'v${e.version}',
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              title: Text(e.reason, style: AppTypography.bodyStrong),
              subtitle: Text(
                friendlyStamp(e.createdAt),
                style: AppTypography.caption,
              ),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (e.before != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(e.before!, style: AppTypography.secondary),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class DetailActions extends StatelessWidget {
  const DetailActions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: children,
    ),
  );
}
