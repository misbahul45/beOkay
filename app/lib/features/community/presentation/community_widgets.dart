import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/pill_button.dart';
import '../data/community_repository.dart';

String dateRange(String start, String end) {
  final s = DateTime.parse(start), e = DateTime.parse(end);
  final day = DateFormat('d MMM', 'id_ID');
  return s.month == e.month && s.year == e.year
      ? '${s.day}–${e.day} ${DateFormat('MMM', 'id_ID').format(e)}'
      : '${day.format(s)} – ${day.format(e)}';
}

({Color tint, Color ink}) statusColors(ChallengeSummary c) {
  if (c.closed) return (tint: AppColors.brandTint, ink: AppColors.brand);
  if (c.scheduled) return (tint: AppColors.softBlue, ink: AppColors.glucoseInk);
  return (tint: AppColors.peach, ink: AppColors.activityInk);
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.tint,
    required this.ink,
  });

  final String label;
  final Color tint, ink;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: tint, borderRadius: AppRadius.pillRadius),
    child: Text(
      label,
      style: AppTypography.caption.copyWith(
        color: ink,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.ratio, this.color});

  final double ratio;
  final Color? color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: LinearProgressIndicator(
        value: ratio.clamp(0, 1).toDouble(),
        minHeight: 10,
        backgroundColor: AppColors.surfaceMuted,
        color: color ?? AppColors.brand,
      ),
    ),
  );
}

class ChallengeCard extends StatelessWidget {
  const ChallengeCard({
    super.key,
    required this.challenge,
    required this.onTap,
  });

  final ChallengeSummary challenge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = challenge;
    final colors = statusColors(c);
    final progress = c.activeDays;
    final label = c.myResult?.label ?? c.statusLabel;
    return Semantics(
      button: true,
      label: [
        c.title,
        dateRange(c.startsOn, c.endsOn),
        label,
        if (progress != null) '$progress dari ${c.targetDays} hari aktif',
      ].join('. '),
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 36,
                      width: 36,
                      decoration: BoxDecoration(
                        color: AppColors.activityTint,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.directions_walk_rounded,
                        size: 18,
                        color: AppColors.activityInk,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.title, style: AppTypography.bodyStrong),
                          Text(
                            [
                              dateRange(c.startsOn, c.endsOn),
                              ?c.communityName,
                              if (c.participantsLabel != null &&
                                  progress == null)
                                c.participantsLabel!,
                            ].join(' · '),
                            style: AppTypography.caption,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    StatusPill(
                      label:
                          c.myResult?.label ??
                          (c.open
                              ? 'Berjalan'
                              : c.scheduled
                              ? 'Segera'
                              : 'Selesai'),
                      tint: colors.tint,
                      ink: colors.ink,
                    ),
                  ],
                ),
                if (progress != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '$progress dari ${c.targetDays} hari aktif',
                    style: AppTypography.secondaryStrong,
                  ),
                  const SizedBox(height: 6),
                  ProgressBar(
                    ratio: c.targetDays == 0 ? 0 : progress / c.targetDays,
                  ),
                  const SizedBox(height: 4),
                  Text(c.statusLabel, style: AppTypography.caption),
                ] else if (c.participating && !c.closed) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Kamu ikut · ${c.statusLabel}',
                    style: AppTypography.caption,
                  ),
                ] else if (!c.closed) ...[
                  const SizedBox(height: 6),
                  Text(c.statusLabel, style: AppTypography.caption),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RecognitionBadge extends StatelessWidget {
  const RecognitionBadge({super.key, required this.recognition});

  final Recognition recognition;

  static ({IconData icon, Color tint, Color ink}) styleOf(String category) =>
      switch (category) {
        'CHALLENGE' => (
          icon: Icons.flag_outlined,
          tint: AppColors.goalTint,
          ink: AppColors.goalInk,
        ),
        'REFLECTION' => (
          icon: Icons.auto_awesome,
          tint: AppColors.brandTint,
          ink: AppColors.brand,
        ),
        'PLAN' => (
          icon: Icons.check_circle_outline,
          tint: AppColors.glucoseTint,
          ink: AppColors.glucoseInk,
        ),
        _ => (
          icon: Icons.event_available_outlined,
          tint: AppColors.mealTint,
          ink: AppColors.mealInk,
        ),
      };

  @override
  Widget build(BuildContext context) {
    final r = recognition;
    final s = styleOf(r.category);
    final wide = MediaQuery.textScalerOf(context).scale(14) > 18;
    final icon = Container(
      height: 36,
      width: 36,
      decoration: BoxDecoration(
        color: r.achieved ? s.tint : AppColors.surfaceMuted,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        r.achieved ? s.icon : Icons.lock_outline,
        size: 18,
        color: r.achieved ? s.ink : AppColors.textSecondary,
      ),
    );
    final label = Text(
      r.title,
      textAlign: wide ? TextAlign.start : TextAlign.center,
      style: AppTypography.caption.copyWith(
        color: r.achieved ? AppColors.textPrimary : AppColors.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    );
    return Semantics(
      label: '${r.achieved ? 'Tercapai' : 'Belum'}: ${r.title}. ${r.detail}',
      excludeSemantics: true,
      child: Container(
        width: wide ? double.infinity : 120,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: r.achieved ? null : Border.all(color: AppColors.border),
        ),
        child: wide
            ? Row(
                children: [
                  icon,
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: label),
                ],
              )
            : Column(children: [icon, const SizedBox(height: 6), label]),
      ),
    );
  }
}

Future<String?> showAliasSheet(
  BuildContext context, {
  required String communityName,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (_) => _AliasSheet(communityName: communityName),
  );
}

class _AliasSheet extends StatefulWidget {
  const _AliasSheet({required this.communityName});
  final String communityName;

  @override
  State<_AliasSheet> createState() => _AliasSheetState();
}

class _AliasSheetState extends State<_AliasSheet> {
  final alias = TextEditingController();
  final form = GlobalKey<FormState>();

  @override
  void dispose() {
    alias.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gabung ${widget.communityName}',
                style: AppTypography.title,
              ),
              const SizedBox(height: 4),
              Text(
                'Anggota lain hanya melihat aliasmu. Data kesehatan tidak pernah dibagikan.',
                style: AppTypography.secondary,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Alias',
                hint: 'mis. pejalan.pagi',
                controller: alias,
                helper:
                    '3–20 karakter. Bukan nama asli, surel, atau nomor telepon.',
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (!RegExp(
                    r'^[A-Za-z0-9][A-Za-z0-9 _.-]{2,19}$',
                  ).hasMatch(t)) {
                    return 'Alias 3–20 karakter: huruf, angka, spasi, titik, garis bawah, atau strip.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              PillButton(
                label: 'Gabung dengan alias ini',
                onPressed: () {
                  if (form.currentState!.validate()) {
                    Navigator.of(context).pop(alias.text.trim());
                  }
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
