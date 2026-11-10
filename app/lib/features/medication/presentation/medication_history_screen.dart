import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../application/medication_controller.dart';
import '../data/medication_repository.dart';

/// Riwayat konfirmasi satu obat. Koreksi selalu memakai alasan dan meninggalkan versi lama.
class MedicationHistoryScreen extends ConsumerWidget {
  const MedicationHistoryScreen({super.key, required this.regimen});
  final Regimen regimen;

  static String _label(String s) => s == 'taken'
      ? 'Sudah diminum'
      : s == 'skipped'
      ? 'Dilewati'
      : 'Tidak diketahui';

  Future<void> _correct(
    BuildContext context,
    WidgetRef ref,
    IntakeRecord r,
  ) async {
    final reason = TextEditingController();
    final form = GlobalKey<FormState>();
    String status = r.status == 'taken' ? 'skipped' : 'taken';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Koreksi konfirmasi'),
          content: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RadioGroup<String>(
                  groupValue: status,
                  onChanged: (v) => set(() => status = v ?? status),
                  child: Column(
                    children: [
                      for (final s in const ['taken', 'skipped'])
                        RadioListTile<String>(
                          value: s,
                          title: Text(_label(s)),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                ),
                AppTextField(
                  label: 'Alasan koreksi',
                  controller: reason,
                  hint: 'mis. Salah menekan tombol',
                  maxLength: 300,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Isi alasan koreksi.' : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(medicationRepositoryProvider).updateIntake(
        regimen.id,
        r.id,
        {
          'status': status,
          'expectedVersion': r.version,
          'reason': reason.text.trim(),
        },
      );
      ref.invalidate(medicationIntakesProvider(regimen.id));
      ref.invalidate(medicationTodayProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(messageFor(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intakes = ref.watch(medicationIntakesProvider(regimen.id));
    return PageScaffold(
      title: regimen.name,
      onBack: () =>
          context.canPop() ? context.pop() : context.go(Routes.medications),
      children: [
        if (regimen.subtitle.isNotEmpty)
          Text(regimen.subtitle, style: AppTypography.secondary),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () =>
                context.push('/medications/${regimen.id}/edit', extra: regimen),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Ubah data obat'),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Semantics(
          header: true,
          child: Text('Riwayat konfirmasi', style: AppTypography.heading),
        ),
        const SizedBox(height: AppSpacing.xs),
        AsyncBody<List<IntakeRecord>>(
          value: intakes,
          onRetry: () => ref.invalidate(medicationIntakesProvider(regimen.id)),
          skeletonRows: 3,
          data: (items) => items.isEmpty
              ? const EmptyState(
                  icon: Icons.history_rounded,
                  title: 'Belum ada konfirmasi',
                  message: 'Konfirmasi yang kamu catat akan muncul di sini.',
                )
              : Column(
                  children: [
                    for (final r in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Material(
                          color: AppColors.surface,
                          borderRadius: AppRadius.cardRadius,
                          child: ListTile(
                            title: Text(
                              _label(r.status),
                              style: AppTypography.bodyStrong,
                            ),
                            subtitle: Text(
                              '${DateFormat('EEE, d MMM · HH:mm', 'id_ID').format(r.eventAt.toLocal())}${r.version > 1 ? ' · dikoreksi' : ''}',
                              style: AppTypography.secondary,
                            ),
                            trailing: TextButton(
                              onPressed: () => _correct(context, ref, r),
                              child: const Text('Koreksi'),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
