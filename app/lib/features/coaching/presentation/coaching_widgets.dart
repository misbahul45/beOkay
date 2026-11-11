import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/choice_chips.dart';
import '../../../core/widgets/pill_button.dart';
import '../data/coaching_repository.dart';

const _weekday = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
const _weekdayLong = [
  'Senin',
  'Selasa',
  'Rabu',
  'Kamis',
  'Jumat',
  'Sabtu',
  'Minggu',
];

int _weekdayIndex(String date) => DateTime.parse(date).weekday - 1;
String dayShort(String date) => _weekday[_weekdayIndex(date)];
String dayLong(String date) => _weekdayLong[_weekdayIndex(date)];

String stateLabel(String state) => switch (state) {
  'OBSERVED' => 'tercatat',
  'USER_CONFIRMED' => 'kamu konfirmasi',
  'NOT_OBSERVED' => 'belum terlihat',
  'RETRACTED' => 'catatannya dihapus',
  'UNKNOWN' => 'tidak diketahui',
  _ => 'direncanakan',
};

class KindIcon extends StatelessWidget {
  const KindIcon({super.key, required this.activity, this.size = 36});

  final bool activity;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    height: size,
    width: size,
    decoration: BoxDecoration(
      color: activity ? AppColors.activityTint : AppColors.mealTint,
      shape: BoxShape.circle,
    ),
    alignment: Alignment.center,
    child: Icon(
      activity ? Icons.directions_walk_rounded : Icons.restaurant_outlined,
      size: size * 0.5,
      color: activity ? AppColors.activityInk : AppColors.mealInk,
    ),
  );
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.cardPadding),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: AppRadius.cardRadius,
    ),
    child: child,
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.action,
    required this.subtitle,
    required this.onMore,
  });

  final CoachingAction action;
  final String subtitle;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      KindIcon(activity: action.isActivity),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(action.title, style: AppTypography.bodyStrong),
            Text(subtitle, style: AppTypography.caption),
          ],
        ),
      ),
      IconButton(
        tooltip: 'Umpan balik',
        onPressed: onMore,
        icon: Icon(Icons.more_horiz, color: AppColors.textSecondary),
      ),
    ],
  );
}

class OpportunityCard extends StatelessWidget {
  const OpportunityCard({
    super.key,
    required this.action,
    required this.onAccept,
    required this.onNotNow,
    required this.onMore,
    this.busy = false,
  });

  final CoachingAction action;
  final VoidCallback onAccept, onNotNow, onMore;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final slot = action.slot == null
        ? ''
        : ' · ${action.slot!.label.toLowerCase()}';
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            action: action,
            subtitle: 'Mulai hari ini$slot',
            onMore: onMore,
          ),
          const SizedBox(height: AppSpacing.xs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm - 2),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kenapa ini?', style: AppTypography.overline),
                const SizedBox(height: 2),
                Text(
                  action.window.isEmpty
                      ? action.evidence
                      : '${action.evidence} (${action.window})',
                  style: AppTypography.secondary.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                if (action.memories.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Memakai ingatan: ${action.memories.join('; ')}',
                    style: AppTypography.caption,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(action.rationale, style: AppTypography.caption),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              PillButton(
                label: 'Coba rencana ini',
                expand: false,
                onPressed: busy ? null : onAccept,
              ),
              PillButton(
                label: 'Bukan sekarang',
                kind: PillButtonKind.secondary,
                expand: false,
                onPressed: busy ? null : onNotNow,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DayChips extends StatelessWidget {
  const DayChips({super.key, required this.days, this.onTapDay});

  final List<DayState> days;
  final ValueChanged<DayState>? onTapDay;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (i, d) in days.indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: _DayChip(day: d, onTap: onTapDay),
          ),
        ],
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.day, this.onTap});

  final DayState day;
  final ValueChanged<DayState>? onTap;

  @override
  Widget build(BuildContext context) {
    final (tint, ink, icon) = switch (day.state) {
      'OBSERVED' => (AppColors.brandTint, AppColors.brand, Icons.check_rounded),
      'USER_CONFIRMED' => (
        AppColors.softBlue,
        AppColors.glucoseInk,
        Icons.check_rounded,
      ),
      'NOT_OBSERVED' => (
        AppColors.surfaceMuted,
        AppColors.textSecondary,
        Icons.remove_rounded,
      ),
      'RETRACTED' => (
        AppColors.surfaceMuted,
        AppColors.textSecondary,
        Icons.undo_rounded,
      ),
      'UNKNOWN' => (
        AppColors.surfaceMuted,
        AppColors.textSecondary,
        Icons.help_outline_rounded,
      ),
      _ when day.today => (AppColors.cream, AppColors.goalInk, Icons.circle),
      _ => (AppColors.surface, AppColors.textSecondary, Icons.circle_outlined),
    };
    final canConfirm =
        onTap != null &&
        (day.state == 'NOT_OBSERVED' ||
            day.state == 'RETRACTED' ||
            (day.today && day.state == 'PLANNED'));
    final label =
        '${dayLong(day.date)}${day.today ? ', hari ini' : ''}: ${stateLabel(day.state)}';
    return Semantics(
      label: label,
      button: canConfirm,
      excludeSemantics: true,
      onTap: canConfirm ? () => onTap!(day) : null,
      child: Material(
        color: tint,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: canConfirm ? () => onTap!(day) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: day.state == 'PLANNED' && !day.today
                ? BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(14),
                  )
                : null,
            child: Column(
              children: [
                Text(
                  dayShort(day.date),
                  style: AppTypography.caption.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(
                  icon,
                  size: day.today && day.state == 'PLANNED' ? 8 : 16,
                  color: ink,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ActionCard extends StatelessWidget {
  const ActionCard({
    super.key,
    required this.action,
    required this.onMore,
    this.onConfirmDay,
    this.busy = false,
  });

  final CoachingAction action;
  final VoidCallback onMore;
  final ValueChanged<DayState>? onConfirmDay;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final today = action.todayState;
    final done = action.dayStates.where((d) => d.done).length;
    final subtitle = action.running
        ? (action.reminderTime == null
              ? 'Tanpa pengingat'
              : 'Pengingat ${action.reminderTime!.replaceAll(':', '.')} aktif')
        : '$done dari ${action.days} hari terlaksana';
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            action: action,
            subtitle: action.slot == null
                ? subtitle
                : '${action.slot!.label} · $subtitle',
            onMore: onMore,
          ),
          const SizedBox(height: AppSpacing.xs),
          DayChips(
            days: action.dayStates,
            onTapDay: action.running && !busy ? onConfirmDay : null,
          ),
          const SizedBox(height: 6),
          Text(
            'Hijau: tercatat · Biru: kamu konfirmasi · Garis: belum terlihat',
            style: AppTypography.caption,
          ),
          if (action.running && today != null && today.state == 'PLANNED') ...[
            const SizedBox(height: AppSpacing.sm),
            PillButton(
              label: 'Sudah kulakukan hari ini',
              icon: Icons.check_rounded,
              expand: false,
              onPressed: busy || onConfirmDay == null
                  ? null
                  : () => onConfirmDay!(today),
            ),
          ],
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.xs),
    child: Semantics(
      header: true,
      child: Text(text.toUpperCase(), style: AppTypography.overline),
    ),
  );
}

class SlotPicker extends StatelessWidget {
  const SlotPicker({super.key, required this.value, required this.onChanged});

  final CoachingSlot? value;
  final ValueChanged<CoachingSlot?> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.xs,
    children: [
      for (final s in CoachingSlot.values)
        PillChip(
          label: s.label,
          selected: value == s,
          onTap: () => onChanged(value == s ? null : s),
        ),
    ],
  );
}

typedef AcceptChoice = ({CoachingSlot? slot, bool reminder});

Future<AcceptChoice?> showAcceptSheet(
  BuildContext context,
  CoachingAction action,
  CoachingSlot? fallback,
) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<AcceptChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (_) =>
        _AcceptSheet(action: action, initial: action.slot ?? fallback),
  );
}

class _AcceptSheet extends StatefulWidget {
  const _AcceptSheet({required this.action, required this.initial});

  final CoachingAction action;
  final CoachingSlot? initial;

  @override
  State<_AcceptSheet> createState() => _AcceptSheetState();
}

class _AcceptSheetState extends State<_AcceptSheet> {
  late CoachingSlot? slot = widget.initial;
  bool reminder = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.action;
    final time = (slot ?? CoachingSlot.midday).time;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(a.title, style: AppTypography.title),
            const SizedBox(height: 4),
            Text(
              '${a.days > 1 ? '${a.days} hari, mulai hari ini' : 'Hari ini'}. ${a.isActivity ? 'Durasi tidak melebihi sesi terpanjangmu.' : 'Hanya bila kamu memang makan pada waktu itu.'}',
              style: AppTypography.secondary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Kapan enaknya?', style: AppTypography.bodyStrong),
            const SizedBox(height: 4),
            SlotPicker(value: slot, onChanged: (v) => setState(() => slot = v)),
            const SizedBox(height: AppSpacing.sm),
            Material(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: SwitchListTile(
                value: reminder,
                onChanged: (v) => setState(() => reminder = v),
                title: Text('Ingatkan aku', style: AppTypography.bodyStrong),
                subtitle: Text(
                  '$time · hanya selama rencana berjalan',
                  style: AppTypography.caption,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Rencana bukan catatan. Yang dihitung hanya yang tercatat atau yang kamu konfirmasi.',
              style: AppTypography.caption,
            ),
            const SizedBox(height: AppSpacing.md),
            PillButton(
              label: 'Mulai rencana',
              onPressed: () =>
                  Navigator.of(context).pop((slot: slot, reminder: reminder)),
            ),
          ],
        ),
      ),
    );
  }
}

typedef FeedbackChoice = ({String kind, CoachingSlot? slot});

Future<FeedbackChoice?> showFeedbackSheet(
  BuildContext context,
  CoachingAction action,
) async {
  FocusManager.instance.primaryFocus?.unfocus();
  final proposed = action.proposed;
  final running = action.running && !proposed;
  final options = <(String, IconData, String)>[
    ('HELPFUL', Icons.thumb_up_alt_outlined, 'Membantu'),
    ('NOT_HELPFUL', Icons.thumb_down_alt_outlined, 'Kurang membantu'),
    if (proposed || running)
      (
        'ALREADY_DONE',
        Icons.check_rounded,
        running ? 'Sudah kulakukan hari ini' : 'Sudah kulakukan',
      ),
    if (proposed) ('NOT_NOW', Icons.schedule_rounded, 'Bukan sekarang'),
    if (proposed || running)
      ('TOO_FREQUENT', Icons.notifications_paused_outlined, 'Terlalu sering'),
    if (proposed || running)
      ('PREFER_DIFFERENT_TIME', Icons.access_time_rounded, 'Waktu lain'),
    if (proposed || running)
      ('PREFER_DIFFERENT_SUGGESTION', Icons.autorenew_rounded, 'Saran lain'),
    ('STOP_THIS_TYPE', Icons.block_rounded, 'Jangan sarankan ini lagi'),
    if (running) ('WITHDRAW', Icons.stop_circle_outlined, 'Hentikan rencana'),
  ];
  final kind = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (s) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.xs,
              ),
              child: Text('Bagaimana saran ini?', style: AppTypography.title),
            ),
            for (final (value, icon, label) in options)
              ListTile(
                leading: Icon(
                  icon,
                  color: value == 'STOP_THIS_TYPE' || value == 'WITHDRAW'
                      ? AppColors.errorForeground
                      : AppColors.brand,
                ),
                title: Text(
                  label,
                  style: AppTypography.body.copyWith(
                    color: value == 'STOP_THIS_TYPE' || value == 'WITHDRAW'
                        ? AppColors.errorForeground
                        : AppColors.textPrimary,
                  ),
                ),
                onTap: () => Navigator.of(s).pop(value),
              ),
          ],
        ),
      ),
    ),
  );
  if (kind == null) return null;
  if (kind != 'PREFER_DIFFERENT_TIME') return (kind: kind, slot: null);
  if (!context.mounted) return null;
  final slot = await showModalBottomSheet<CoachingSlot>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (s) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Text('Waktu yang lebih cocok', style: AppTypography.title),
          ),
          for (final v in CoachingSlot.values)
            ListTile(
              title: Text('${v.label} (${v.time})', style: AppTypography.body),
              trailing: action.slot == v
                  ? Icon(Icons.check_rounded, color: AppColors.brand)
                  : null,
              onTap: () => Navigator.of(s).pop(v),
            ),
        ],
      ),
    ),
  );
  return slot == null ? null : (kind: kind, slot: slot);
}

String feedbackMessage(
  String kind, {
  bool running = false,
  CoachingSlot? slot,
}) => switch (kind) {
  'HELPFUL' => 'Terima kasih. Saran sejenis akan diutamakan.',
  'NOT_HELPFUL' => 'Terima kasih. Saran sejenis akan dikurangi.',
  'ALREADY_DONE' =>
    running
        ? 'Hari ini ditandai sudah dilakukan.'
        : 'Bagus! Usulan ini disimpan dulu.',
  'NOT_NOW' =>
    'Oke, tidak dulu. Usulan ini muncul lagi paling cepat 3 hari lagi.',
  'TOO_FREQUENT' => 'Saran dan pengingat akan dikurangi.',
  'PREFER_DIFFERENT_TIME' =>
    'Waktu diubah ke ${slot?.label.toLowerCase() ?? 'pilihanmu'}.',
  'PREFER_DIFFERENT_SUGGESTION' => 'Usulan lain akan disiapkan.',
  'STOP_THIS_TYPE' => 'Saran jenis ini tidak akan muncul lagi.',
  'WITHDRAW' => 'Rencana dihentikan.',
  _ => 'Tersimpan.',
};
