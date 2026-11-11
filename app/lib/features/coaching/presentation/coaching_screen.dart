import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../application/coaching_controller.dart';
import '../data/coaching_repository.dart';
import 'coaching_widgets.dart';

class CoachingScreen extends ConsumerStatefulWidget {
  const CoachingScreen({super.key});

  @override
  ConsumerState<CoachingScreen> createState() => _CoachingScreenState();
}

class _CoachingScreenState extends ConsumerState<CoachingScreen> {
  bool busy = false;

  CoachingRepository get _repo => ref.read(coachingRepositoryProvider);

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => busy = true);
    try {
      await action();
      ref.invalidate(coachingOverviewProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(done)));
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

  Future<void> _accept(CoachingAction a, CoachingSlot? fallback) async {
    final choice = await showAcceptSheet(context, a, fallback);
    if (choice == null) return;
    await _run(
      () => _repo.accept(a.id, slot: choice.slot, reminder: choice.reminder),
      choice.reminder
          ? 'Rencana dimulai. Pengingat aktif.'
          : 'Rencana dimulai.',
    );
  }

  Future<void> _more(CoachingAction a) async {
    final choice = await showFeedbackSheet(context, a);
    if (choice == null) return;
    if (choice.kind == 'WITHDRAW') {
      await _run(() => _repo.withdraw(a.id), feedbackMessage('WITHDRAW'));
      return;
    }
    await _run(
      () => _repo.feedback(a.id, choice.kind, slot: choice.slot),
      feedbackMessage(choice.kind, running: !a.proposed, slot: choice.slot),
    );
  }

  Future<void> _confirm(CoachingAction a, DayState d) async {
    if (!d.today) {
      final ok =
          await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: Text('Tandai ${dayLong(d.date)} sudah dilakukan?'),
              content: const Text(
                'Ini tercatat sebagai konfirmasimu sendiri, terpisah dari catatan yang terekam.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(c).pop(false),
                  child: const Text('Batal'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(c).pop(true),
                  child: const Text('Tandai'),
                ),
              ],
            ),
          ) ==
          true;
      if (!ok) return;
    }
    await _run(
      () => _repo.confirm(a.id, d.date),
      '${d.today ? 'Hari ini' : dayLong(d.date)} ditandai sudah dilakukan.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(coachingOverviewProvider);
    return PageScaffold(
      title: 'Rencana kecil',
      onRefresh: () async {
        ref.invalidate(coachingOverviewProvider);
        await ref
            .read(coachingOverviewProvider.future)
            .then<void>((_) {}, onError: (_) {});
      },
      children: [
        overview.when(
          loading: () => const SkeletonList(rows: 3),
          error: (e, _) => ErrorState(
            error: e,
            onRetry: () => ref.invalidate(coachingOverviewProvider),
          ),
          data: (o) => o.consentRequired
              ? InfoCard(
                  title: 'Persetujuan diperlukan',
                  text:
                      'Rencana kecil memakai catatanmu dan saran personal. Aktifkan keduanya di Persetujuan data.',
                  action: PillButton(
                    label: 'Kelola persetujuan',
                    onPressed: () => context.push(Routes.consentManagement),
                  ),
                )
              : _Body(
                  overview: o,
                  busy: busy,
                  onAccept: (a) => _accept(a, o.slot),
                  onNotNow: (a) => _run(
                    () => _repo.feedback(a.id, 'NOT_NOW'),
                    feedbackMessage('NOT_NOW'),
                  ),
                  onMore: _more,
                  onConfirm: _confirm,
                ),
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.overview,
    required this.busy,
    required this.onAccept,
    required this.onNotNow,
    required this.onMore,
    required this.onConfirm,
  });

  final CoachingOverview overview;
  final bool busy;
  final ValueChanged<CoachingAction> onAccept, onNotNow, onMore;
  final void Function(CoachingAction, DayState) onConfirm;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final r = o.reflection;
    final children = <Widget>[];
    void gap() => children.add(const SizedBox(height: AppSpacing.lg));
    if (r != null && (r.available || r.done)) {
      children.add(_ReflectionEntry(status: r));
      gap();
    }
    children.add(const SectionTitle('Peluang dari catatanmu'));
    if (o.opportunities.isEmpty) {
      children.add(
        Text(
          'Belum ada peluang yang didukung catatanmu. beOkay hanya menyarankan bila catatanmu menunjukkannya.',
          style: AppTypography.secondary,
        ),
      );
    }
    for (final (i, a) in o.opportunities.indexed) {
      if (i > 0) children.add(const SizedBox(height: AppSpacing.sm));
      children.add(
        OpportunityCard(
          action: a,
          busy: busy,
          onAccept: () => onAccept(a),
          onNotNow: () => onNotNow(a),
          onMore: () => onMore(a),
        ),
      );
    }
    void section(String title, List<CoachingAction> items) {
      if (items.isEmpty) return;
      gap();
      children.add(SectionTitle(title));
      for (final (i, a) in items.indexed) {
        if (i > 0) children.add(const SizedBox(height: AppSpacing.sm));
        children.add(
          ActionCard(
            action: a,
            busy: busy,
            onMore: () => onMore(a),
            onConfirmDay: (d) => onConfirm(a, d),
          ),
        );
      }
    }

    section('Rencana berjalan', o.running);
    section('Selesai', o.ended);
    gap();
    children.add(
      InfoCard(
        tone: InfoTone.neutral,
        text:
            'Rencana bukan catatan. Yang dihitung hanya yang tercatat atau yang kamu konfirmasi. Belum terlihat bukan berarti gagal.',
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _ReflectionEntry extends StatelessWidget {
  const _ReflectionEntry({required this.status});

  final ReflectionStatus status;

  @override
  Widget build(BuildContext context) {
    final done = status.done;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: done ? AppColors.brandTint : AppColors.cream,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            done ? 'Refleksi mingguan selesai' : 'Refleksi mingguan siap',
            style: AppTypography.bodyStrong,
          ),
          const SizedBox(height: 2),
          Text(
            done
                ? 'Lihat lagi ringkasan dan penyesuaian yang kamu pilih.'
                : 'Lihat yang sudah berjalan dan atur langkah minggu depan. Sekitar 2 menit.',
            style: AppTypography.secondary,
          ),
          const SizedBox(height: AppSpacing.sm),
          PillButton(
            label: done ? 'Lihat refleksi' : 'Mulai refleksi',
            kind: done ? PillButtonKind.light : PillButtonKind.primary,
            expand: false,
            onPressed: () => context.push(Routes.reflection),
          ),
        ],
      ),
    );
  }
}
