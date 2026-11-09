import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ids/record_id.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../application/medication_controller.dart';
import '../data/medication_repository.dart';

/// Self-reported medication list and today's schedule. A schedule is never evidence of intake.
class MedicationScreen extends ConsumerWidget {
  const MedicationScreen({super.key});

  Future<void> _act(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    try {
      await action();
      ref.invalidate(medicationTodayProvider);
      ref.invalidate(medicationListProvider);
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(messageFor(error))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(medicationTodayProvider);
    final list = ref.watch(medicationListProvider);
    final repo = ref.watch(medicationRepositoryProvider);
    return PageScaffold(
      title: 'Obat',
      onBack: () => context.canPop() ? context.pop() : context.go(Routes.home),
      bottom: PillButton(label: 'Tambah obat', icon: Icons.add_rounded, onPressed: () => context.push(Routes.addMedication)),
      onRefresh: () async {
        ref.invalidate(medicationTodayProvider);
        ref.invalidate(medicationListProvider);
      },
      children: [
        const InfoCard(tone: InfoTone.neutral, text: 'Daftar ini hanya catatanmu sendiri. Jadwal bukan bukti kamu sudah minum, dan yang belum dikonfirmasi tetap "belum dikonfirmasi".'),
        const SizedBox(height: AppSpacing.md),
        Semantics(header: true, child: Text('Jadwal hari ini', style: AppTypography.heading)),
        const SizedBox(height: AppSpacing.xs + 2),
        AsyncBody<MedicationToday>(
          value: today,
          onRetry: () => ref.invalidate(medicationTodayProvider),
          skeletonRows: 2,
          data: (t) => t.items.isEmpty
              ? Text('Tidak ada jadwal hari ini.', style: AppTypography.secondary)
              : Column(
                  children: [
                    for (final o in t.items) ...[
                      _OccurrenceCard(
                        item: o,
                        onTaken: () => _act(context, ref, () => repo.createIntake(o.regimenId, {'id': newRecordId(), 'scheduleId': o.scheduleId, 'scheduledAt': o.scheduledAt, 'status': 'taken', 'takenAt': DateTime.now().toUtc().toIso8601String()})),
                        onSkipped: () => _act(context, ref, () => repo.createIntake(o.regimenId, {'id': newRecordId(), 'scheduleId': o.scheduleId, 'scheduledAt': o.scheduledAt, 'status': 'skipped'})),
                        onUndo: o.intakeId == null ? null : () => _act(context, ref, () => repo.updateIntake(o.regimenId, o.intakeId!, {'archived': true, 'expectedVersion': o.intakeVersion, 'reason': 'Dibatalkan pengguna'})),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        Semantics(header: true, child: Text('Daftar obat', style: AppTypography.heading)),
        const SizedBox(height: AppSpacing.xs + 2),
        AsyncBody<List<Regimen>>(
          value: list,
          onRetry: () => ref.invalidate(medicationListProvider),
          skeletonRows: 2,
          data: (items) => items.isEmpty
              ? EmptyState(icon: Icons.medication_outlined, title: 'Belum ada obat', message: 'Tambahkan nama, kekuatan, dan instruksi yang kamu terima. Kamu yang memegang kendali.', actionLabel: 'Tambah obat', onAction: () => context.push(Routes.addMedication))
              : Column(
                  children: [
                    for (final r in items) ...[
                      _RegimenCard(
                        regimen: r,
                        onToggle: () => _act(context, ref, () => repo.updateRegimen(r.id, {'status': r.status == 'active' ? 'paused' : 'active', 'expectedVersion': r.version, 'reason': 'Diubah pengguna'})),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _OccurrenceCard extends StatelessWidget {
  const _OccurrenceCard({required this.item, required this.onTaken, required this.onSkipped, required this.onUndo});
  final Occurrence item;
  final VoidCallback onTaken, onSkipped;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (item.status) {
      'taken' => ('Sudah diminum', InfoTone.info),
      'skipped' => ('Dilewati', InfoTone.neutral),
      _ => ('Belum dikonfirmasi', InfoTone.warning),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.cardRadius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('${item.localTime} · ${item.name}', style: AppTypography.title)),
              StatusBadge(label: label, tone: tone),
            ],
          ),
          if (item.strength != null) Text(item.strength!, style: AppTypography.secondary),
          const SizedBox(height: AppSpacing.sm),
          if (item.status == 'unknown')
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                PillButton(label: 'Sudah diminum', icon: Icons.check_rounded, expand: false, onPressed: onTaken),
                PillButton(label: 'Lewati', kind: PillButtonKind.secondary, expand: false, onPressed: onSkipped),
              ],
            )
          else if (onUndo != null)
            TextButton(onPressed: onUndo, child: const Text('Batalkan konfirmasi')),
        ],
      ),
    );
  }
}

class _RegimenCard extends StatelessWidget {
  const _RegimenCard({required this.regimen, required this.onToggle});
  final Regimen regimen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final active = regimen.status == 'active';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.cardRadius),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(regimen.name, style: AppTypography.title),
                if (regimen.subtitle.isNotEmpty) Text(regimen.subtitle, style: AppTypography.secondary),
                Text(regimen.scheduleLabel, style: AppTypography.caption),
                if (regimen.instructions != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(regimen.instructions!, style: AppTypography.caption)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          TextButton(onPressed: () => context.push('/medications/${regimen.id}/history', extra: regimen), child: const Text('Riwayat')),
          TextButton(onPressed: onToggle, child: Text(active ? 'Jeda' : 'Aktifkan')),
        ],
      ),
    );
  }
}
