import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/record_reason_dialog.dart';
import '../application/clinical_controller.dart';
import '../data/clinical_models.dart';
import 'clinical_forms.dart';
import 'clinical_screen.dart';

class ClinicalHistoryScreen extends ConsumerWidget {
  const ClinicalHistoryScreen.vital(this.code, {super.key}) : isLab = false;
  const ClinicalHistoryScreen.lab(this.code, {super.key}) : isLab = true;
  final String code;
  final bool isLab;

  Future<void> _archive(
    BuildContext context,
    WidgetRef ref, {
    required String id,
    required int version,
  }) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const RecordReasonDialog(restoring: false),
    );
    if (reason == null || !context.mounted) return;
    final repo = ref.read(clinicalRepositoryProvider);
    final body = {
      'expectedVersion': version,
      'reason': reason,
      'archived': true,
    };
    try {
      if (isLab) {
        await repo.saveLab(body, id: id);
        ref.invalidate(labHistoryProvider(code));
      } else {
        await repo.saveVital(body, id: id);
        ref.invalidate(vitalHistoryProvider(code));
      }
      ref.invalidate(clinicalSummaryProvider);
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
    final title = isLab
        ? (labTests[code]?.$1 ?? code)
        : (vitalKinds[code]?.$1 ?? code);
    final rows = isLab
        ? ref
              .watch(labHistoryProvider(code))
              .whenData(
                (v) => [
                  for (final r in v)
                    (
                      r.id,
                      r.version,
                      r.display,
                      'Sampel ${friendlyDate(r.sampledAt)}${r.labName == null ? '' : ' · ${r.labName}'}',
                      r as Object,
                    ),
                ],
              )
        : ref
              .watch(vitalHistoryProvider(code))
              .whenData(
                (v) => [
                  for (final r in v)
                    (
                      r.id,
                      r.version,
                      r.display,
                      '${friendlyDate(r.localDate)} · ${r.localTime}',
                      r as Object,
                    ),
                ],
              );
    return PageScaffold(
      title: title,
      children: [
        rows.when(
          loading: () => const SkeletonList(rows: 3),
          error: (e, _) => ErrorState(
            error: e,
            onRetry: () => ref.invalidate(
              isLab ? labHistoryProvider(code) : vitalHistoryProvider(code),
            ),
          ),
          data: (items) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (items.isEmpty)
                Text('Belum ada catatan.', style: AppTypography.secondary),
              for (final (id, version, display, subtitle, record) in items)
                Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: ListTile(
                    title: Text(display, style: AppTypography.bodyStrong),
                    subtitle: Text(subtitle),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Pilihan',
                      onSelected: (v) {
                        if (v == 'edit') {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => isLab
                                  ? LabFormScreen(initial: record as LabRecord)
                                  : VitalFormScreen(
                                      initial: record as VitalRecord,
                                    ),
                            ),
                          );
                        } else {
                          _archive(context, ref, id: id, version: version);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Koreksi')),
                        PopupMenuItem(
                          value: 'archive',
                          child: Text('Arsipkan'),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              PillButton(
                label: 'Tambah catatan',
                icon: Icons.add,
                kind: PillButtonKind.secondary,
                onPressed: () => context.push(
                  isLab
                      ? '${Routes.addLab}?test=$code'
                      : '${Routes.addVital}?kind=$code',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
