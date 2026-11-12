import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/ids/record_id.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/beokay_avatar.dart';
import '../../../core/widgets/choice_chips.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../goals/application/goals_controller.dart';
import '../../interventions/application/intervention_controller.dart';
import '../../memory/application/memory_controller.dart';
import '../application/coaching_controller.dart';
import '../data/coaching_repository.dart';
import 'coaching_widgets.dart';
import '../../../core/analytics/usage_tracker.dart';

const _moods = [('GOOD', 'Lancar'), ('MIXED', 'Campur'), ('HARD', 'Berat')];
const _hardest = [
  ('TIME', 'Waktu'),
  ('FORGOT', 'Lupa'),
  ('ENERGY', 'Tenaga'),
  ('MOTIVATION', 'Motivasi'),
  ('OTHER', 'Hal lain'),
];

String weekRange(String start, String end) {
  final s = DateTime.parse(start), e = DateTime.parse(end);
  final month = DateFormat('MMMM', 'id_ID');
  return s.month == e.month
      ? '${s.day}–${e.day} ${month.format(e)}'
      : '${s.day} ${month.format(s)} – ${e.day} ${month.format(e)}';
}

class ReflectionScreen extends ConsumerStatefulWidget {
  const ReflectionScreen({super.key});

  @override
  ConsumerState<ReflectionScreen> createState() => _ReflectionScreenState();
}

class _ReflectionScreenState extends ConsumerState<ReflectionScreen> {
  final operationId = newRecordId();
  final note = TextEditingController();
  int step = 0;
  String? mood;
  final hardest = <String>{};
  final chosen = <String>{};
  CoachingSlot? slot;
  bool slotTouched = false;
  bool remember = true;
  bool busy = false;
  ({String barrier, String key})? strategy;
  bool hardestSeeded = false;
  List<String>? recognition;

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> _submit(Reflection r) async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => busy = true);
    try {
      final picked = slotTouched ? slot : null;
      final result = await ref
          .read(coachingRepositoryProvider)
          .submitCheckin(
            operationId: operationId,
            weekStart: r.weekStart,
            mood: mood,
            hardest: hardest.toList(),
            note: note.text.trim().isEmpty ? null : note.text.trim(),
            adjustments: r.adjustments
                .where((a) => chosen.contains(a.goalId))
                .toList(),
            preferredSlot: picked,
            rememberSlot: picked != null && r.memoryAvailable && remember,
            strategy: strategy != null && hardest.contains(strategy!.barrier)
                ? strategy
                : null,
          );
      if (strategy != null) {
        ref
            .read(usageTrackerProvider)
            .track('strategy_chosen', domain: 'coaching');
      }
      ref.invalidate(coachingOverviewProvider);
      ref.invalidate(goalsListProvider);
      ref.invalidate(openInterventionsProvider);
      ref.invalidate(memoryOverviewProvider);
      if (mounted) {
        setState(() {
          recognition = result.recognition;
          step = 3;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _back() {
    if (step > 0 && step < 3) {
      setState(() => step--);
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(reflectionProvider);
    return PopScope(
      canPop: step == 0 || step == 3,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: PageScaffold(
        title: 'Refleksi mingguan',
        onBack: _back,
        children: [
          value.when(
            loading: () => const SkeletonList(rows: 4),
            error: (e, _) => ErrorState(
              error: e,
              onRetry: () => ref.invalidate(reflectionProvider),
            ),
            data: (r) {
              if (r.consentRequired) {
                return InfoCard(
                  title: 'Persetujuan diperlukan',
                  text:
                      'Refleksi memakai ringkasan catatanmu. Aktifkan "Membuat ringkasan dan insight deskriptif" di Persetujuan data.',
                  action: PillButton(
                    label: 'Kelola persetujuan',
                    onPressed: () => context.push(Routes.consentManagement),
                  ),
                );
              }
              return switch (step) {
                0 => _Summary(
                  r: r,
                  onNext: r.done == null
                      ? () => setState(() {
                          if (!hardestSeeded) {
                            hardestSeeded = true;
                            hardest.addAll(r.memoryBarriers);
                          }
                          step = 1;
                        })
                      : null,
                ),
                1 => _Questions(
                  mood: mood,
                  hardest: hardest,
                  note: note,
                  onMood: (v) => setState(() => mood = mood == v ? null : v),
                  onHardest: (v) => setState(
                    () => hardest.contains(v)
                        ? hardest.remove(v)
                        : hardest.add(v),
                  ),
                  onNext: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    setState(() => step = 2);
                  },
                ),
                2 => _Adjust(
                  r: r,
                  hardest: hardest,
                  strategy: strategy,
                  onStrategy: (v) =>
                      setState(() => strategy = strategy == v ? null : v),
                  chosen: chosen,
                  slot: slotTouched ? slot : r.preferredSlot,
                  showRemember:
                      slotTouched && slot != null && r.memoryAvailable,
                  remember: remember,
                  busy: busy,
                  onToggle: (id, v) =>
                      setState(() => v ? chosen.add(id) : chosen.remove(id)),
                  onSlot: (v) => setState(() {
                    slot = v;
                    slotTouched = true;
                  }),
                  onRemember: (v) => setState(() => remember = v),
                  onSave: () => _submit(r),
                ),
                _ => _Done(recognition: recognition ?? const []),
              };
            },
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.r, required this.onNext});

  final Reflection r;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final good = r.positives.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          decoration: BoxDecoration(
            color: AppColors.brandTint,
            borderRadius: BorderRadius.circular(AppRadius.hero),
          ),
          child: Row(
            children: [
              const BeOkayAvatar(size: 56, animate: false),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      weekRange(r.weekStart, r.weekEnd).toUpperCase(),
                      style: AppTypography.overline.copyWith(
                        color: AppColors.brand,
                      ),
                    ),
                    Text(
                      good
                          ? 'Ada yang berjalan baik minggu ini'
                          : 'Minggu ini belum banyak catatan',
                      style: AppTypography.title.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (r.done != null) ...[
          const SizedBox(height: AppSpacing.sm),
          const InfoCard(
            title: 'Refleksi ini sudah tersimpan',
            text:
                'Kamu bisa melihat ringkasannya di sini. Refleksi berikutnya dibuka minggu depan.',
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        const SectionTitle('Yang berjalan baik'),
        _Panel(
          children: good
              ? [for (final p in r.positives) _Check(text: p)]
              : [
                  Text(
                    'Tidak apa-apa. Kita mulai lagi dari langkah yang sangat kecil.',
                    style: AppTypography.secondary,
                  ),
                ],
        ),
        if (r.learned.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          const SectionTitle('Yang kupelajari minggu lalu'),
          _Panel(
            children: [
              for (final l in r.learned)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(l, style: AppTypography.body),
                ),
              const SizedBox(height: 4),
              Text(
                'Disusun dari keputusan dan catatanmu sendiri.',
                style: AppTypography.caption,
              ),
            ],
          ),
        ],
        if (r.previousStrategy case final p?) ...[
          const SizedBox(height: AppSpacing.lg),
          const SectionTitle('Cara yang kamu coba'),
          _Panel(
            children: [
              Text(p.title, style: AppTypography.bodyStrong),
              Text(
                p.confirmedDays > 0
                    ? 'Kamu jalankan ${p.confirmedDays} dari ${p.days} hari${p.barrierLabel == null ? '' : ' · hambatan ${p.barrierLabel!.toLowerCase()}'}.'
                    : 'Belum ada hari yang kamu konfirmasi. Tidak apa-apa, kita bisa coba cara lain.',
                style: AppTypography.secondary,
              ),
            ],
          ),
        ],
        if (r.actionTitles.isNotEmpty || r.fromAssistant > 0) ...[
          const SizedBox(height: AppSpacing.lg),
          const SectionTitle('Rencana'),
          _Panel(
            children: [
              Text(
                [
                  if (r.observed > 0) '${r.observed} tercatat',
                  if (r.confirmed > 0) '${r.confirmed} kamu konfirmasi',
                  if (r.fromAssistant > 0)
                    '${r.fromAssistant} dari saran asisten',
                  if (r.notObserved > 0) '${r.notObserved} belum terlihat',
                  if (r.planned > 0) '${r.planned} masih direncanakan',
                ].join(' · '),
                style: AppTypography.body,
              ),
              if (r.notObserved > 0) ...[
                const SizedBox(height: 4),
                Text(
                  'Belum terlihat bukan berarti gagal — mungkin hanya belum dicatat.',
                  style: AppTypography.caption,
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        const SectionTitle('Tujuan & kelengkapan data'),
        _Panel(
          children: [
            for (final g in r.goals) ...[
              Text(g.title, style: AppTypography.bodyStrong),
              const SizedBox(height: 4),
              ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ((g.ratio ?? 0).clamp(0, 1)).toDouble(),
                    minHeight: 8,
                    backgroundColor: AppColors.surfaceMuted,
                    color: AppColors.brand,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                g.value == null
                    ? 'Belum ada catatan untuk tujuan ini'
                    : '${_n(g.value!)} dari ${_n(g.target)}',
                style: AppTypography.caption,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            Text(
              'Data tercatat di ${r.recordedDays} dari ${r.totalDays} hari',
              style: AppTypography.secondary,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (onNext != null) PillButton(label: 'Lanjut', onPressed: onNext),
      ],
    );
  }
}

String _n(double v) =>
    v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);

class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.cardPadding),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: AppRadius.cardRadius,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

class _Check extends StatelessWidget {
  const _Check({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_rounded, size: 18, color: AppColors.brand),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: Text(text, style: AppTypography.body)),
      ],
    ),
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.sm + 2),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text(text, style: AppTypography.body),
  );
}

class _Questions extends StatelessWidget {
  const _Questions({
    required this.mood,
    required this.hardest,
    required this.note,
    required this.onMood,
    required this.onHardest,
    required this.onNext,
  });

  final String? mood;
  final Set<String> hardest;
  final TextEditingController note;
  final ValueChanged<String> onMood, onHardest;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _Bubble('Bagaimana minggu ini menurutmu?'),
      Wrap(
        spacing: AppSpacing.xs,
        children: [
          for (final (v, l) in _moods)
            PillChip(label: l, selected: mood == v, onTap: () => onMood(v)),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      const _Bubble(
        'Bagian mana yang paling sulit? Boleh pilih lebih dari satu.',
      ),
      Wrap(
        spacing: AppSpacing.xs,
        children: [
          for (final (v, l) in _hardest)
            PillChip(
              label: l,
              selected: hardest.contains(v),
              onTap: () => onHardest(v),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      TextField(
        controller: note,
        maxLength: 280,
        minLines: 1,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Catatan singkat (opsional)',
          helperText: 'Hanya untukmu. Ikut tersimpan di refleksi ini.',
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      PillButton(label: 'Lanjut', onPressed: onNext),
    ],
  );
}

class _Adjust extends StatelessWidget {
  const _Adjust({
    required this.r,
    required this.hardest,
    required this.strategy,
    required this.onStrategy,
    required this.chosen,
    required this.slot,
    required this.showRemember,
    required this.remember,
    required this.busy,
    required this.onToggle,
    required this.onSlot,
    required this.onRemember,
    required this.onSave,
  });

  final Reflection r;
  final Set<String> hardest;
  final ({String barrier, String key})? strategy;
  final ValueChanged<({String barrier, String key})> onStrategy;
  final Set<String> chosen;
  final CoachingSlot? slot;
  final bool showRemember, remember, busy;
  final void Function(String, bool) onToggle;
  final ValueChanged<CoachingSlot?> onSlot;
  final ValueChanged<bool> onRemember;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _Bubble('Apa yang ingin kita sesuaikan minggu depan?'),
      const SizedBox(height: AppSpacing.sm),
      if (r.adjustments.isEmpty)
        Text(
          'Tidak ada target yang perlu diubah. Tujuanmu tetap.',
          style: AppTypography.secondary,
        ),
      for (final a in r.adjustments) ...[
        Material(
          color: AppColors.surface,
          borderRadius: AppRadius.cardRadius,
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile(
            value: chosen.contains(a.goalId),
            onChanged: (v) => onToggle(a.goalId, v),
            title: Text(a.title, style: AppTypography.bodyStrong),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${a.raises ? 'Naikkan' : 'Ringankan'} target: ${a.change}',
                  style: AppTypography.secondaryStrong.copyWith(
                    color: AppColors.brand,
                  ),
                ),
                Text(
                  '${a.basis} Bisa diubah lagi kapan saja.',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
      ],
      for (final b in _hardest.where(
        (h) =>
            hardest.contains(h.$1) && (r.strategies[h.$1]?.isNotEmpty ?? false),
      )) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Cara mengatasi: ${b.$2.toLowerCase()}',
          style: AppTypography.bodyStrong,
        ),
        const SizedBox(height: 2),
        Text(
          'Pilih satu untuk dicoba 7 hari. Boleh dilewati.',
          style: AppTypography.caption,
        ),
        const SizedBox(height: 4),
        for (final st in r.strategies[b.$1]!)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Material(
              color: AppColors.surface,
              borderRadius: AppRadius.cardRadius,
              clipBehavior: Clip.antiAlias,
              child: Semantics(
                selected: strategy?.key == st.key,
                child: ListTile(
                  onTap: () => onStrategy((barrier: b.$1, key: st.key)),
                  leading: Icon(
                    strategy?.key == st.key
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: strategy?.key == st.key
                        ? AppColors.brand
                        : AppColors.decorative,
                  ),
                  title: Text(st.title, style: AppTypography.bodyStrong),
                  subtitle: Text(st.detail, style: AppTypography.caption),
                ),
              ),
            ),
          ),
      ],
      if (hardest.isNotEmpty && !r.strategiesReviewed)
        Text(
          'Daftar cara ini masih menunggu tinjauan tenaga kesehatan.',
          style: AppTypography.caption,
        ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        'Waktu yang paling enak untuk rencana',
        style: AppTypography.bodyStrong,
      ),
      const SizedBox(height: 4),
      SlotPicker(value: slot, onChanged: onSlot),
      if (showRemember)
        Material(
          color: AppColors.surface,
          borderRadius: AppRadius.cardRadius,
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile(
            value: remember,
            onChanged: onRemember,
            title: Text(
              'Ingat waktu ini untuk saran berikutnya',
              style: AppTypography.body,
            ),
            subtitle: Text(
              'Tersimpan di Memori & personalisasi; bisa dihapus kapan saja.',
              style: AppTypography.caption,
            ),
          ),
        ),
      const SizedBox(height: AppSpacing.sm),
      const InfoCard(
        tone: InfoTone.neutral,
        text:
            'Tidak ada yang berubah tanpa persetujuanmu. Target klinis tidak pernah diubah otomatis.',
      ),
      const SizedBox(height: AppSpacing.md),
      PillButton(
        label: 'Simpan refleksi',
        loading: busy,
        onPressed: busy ? null : onSave,
      ),
    ],
  );
}

class _Done extends StatelessWidget {
  const _Done({required this.recognition});

  final List<String> recognition;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: BoxDecoration(
          color: AppColors.brandTint,
          borderRadius: AppRadius.cardRadius,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in recognition)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 18, color: AppColors.brand),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(child: Text(r, style: AppTypography.bodyStrong)),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        'Terima kasih sudah meluangkan waktu. Usaha kecil yang konsisten lebih penting daripada angka sempurna.',
        style: AppTypography.secondary,
      ),
      const SizedBox(height: AppSpacing.lg),
      PillButton(
        label: 'Lihat rencana kecil',
        onPressed: () => context.pushReplacement(Routes.coaching),
      ),
      const SizedBox(height: AppSpacing.xs),
      PillButton(
        label: 'Selesai',
        kind: PillButtonKind.ghost,
        onPressed: () => context.pop(),
      ),
    ],
  );
}
