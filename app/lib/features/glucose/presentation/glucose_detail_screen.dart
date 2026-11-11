import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/format/formatters.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/health_card.dart';
import '../../../core/widgets/health_error.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/record_reason_dialog.dart';
import '../../today/application/today_controller.dart';
import '../application/glucose_controller.dart';
import '../data/glucose_models.dart';
import 'glucose_form_screen.dart';

class GlucoseDetailScreen extends ConsumerStatefulWidget {
  const GlucoseDetailScreen({super.key, required this.id, this.edit = false});
  final String id;
  final bool edit;
  @override
  ConsumerState<GlucoseDetailScreen> createState() =>
      _GlucoseDetailScreenState();
}

class _GlucoseDetailScreenState extends ConsumerState<GlucoseDetailScreen> {
  bool busy = false;
  String? error;
  Future<void> archive(GlucoseRecord record) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => RecordReasonDialog(restoring: record.archived),
    );
    if (reason == null || !mounted) return;
    final repo = ref.read(glucoseRepositoryProvider);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await repo.save({
        'expectedVersion': record.version,
        'reason': reason,
        'archived': !record.archived,
      }, id: record.id);
      if (!mounted || !repo.isCurrentAccount()) return;
      ref.invalidate(glucoseProvider(record.id));
      ref.invalidate(glucosePageProvider);
      ref.invalidate(glucoseDayProvider);
      ref.invalidate(todayProvider);
    } catch (e) {
      if (mounted) setState(() => error = messageFor(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(glucoseProvider(widget.id))
      .when(
        skipLoadingOnRefresh: false,
        skipLoadingOnReload: false,
        loading: () => const PageScaffold(
          title: 'Memuat pengukuran',
          children: [SkeletonList()],
        ),
        error: (e, _) => PageScaffold(
          title: 'Detail glukosa',
          children: [
            HealthError(
              error: e,
              retry: () => ref.invalidate(glucoseProvider(widget.id)),
            ),
          ],
        ),
        data: (record) {
          if (widget.edit) {
            return GlucoseFormScreen(
              key: ValueKey(record.version),
              initial: record,
            );
          }
          return PageScaffold(
            title: 'Detail glukosa',
            onBack: () =>
                context.canPop() ? context.pop() : context.go(Routes.glucose),
            actions: [
              IconButton(
                tooltip: 'Beranda',
                onPressed: () => context.go(Routes.home),
                icon: const Icon(Icons.home_outlined),
              ),
            ],
            children: [
              Text(record.label, style: AppTypography.headline),
              Text(
                '${record.localDate} · ${record.localTime} · ${record.timezone}',
              ),
              const SizedBox(height: 16),
              HealthCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nilai asli: ${record.originalValue} ${record.originalUnit}',
                    ),
                    if (record.originalUnit != record.displayUnit)
                      const Text(
                        'Nilai tampilan dikonversi; data asli tetap tersimpan.',
                      ),
                    const Text(
                      'Sumber: glukometer manual\nJenis: pengukuran darah kapiler',
                    ),
                    Text('Konteks: ${glucoseContexts[record.mealContext]}'),
                    Text(record.qualityLabel),
                    if (record.version > 1 || record.archived)
                      Text(
                        revisionLabel(
                          record.version,
                          archived: record.archived,
                        ),
                      ),
                    if (record.notes != null) Text(record.notes!),
                    ExpansionTile(
                      title: const Text('Provenansi pengukuran'),
                      children: [
                        Text(
                          'Diukur: ${record.measuredAt.toIso8601String()}\nDicatat: ${record.recordedAt}\nDiterima: ${record.receivedAt}\nKanonik: ${record.valueMgDl} mg/dL',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (error != null) ...[
                ErrorBanner(error!),
                TextButton(
                  onPressed: () => ref.invalidate(glucoseProvider(record.id)),
                  child: const Text('Muat ulang catatan'),
                ),
              ],
              if (!record.archived)
                PillButton(
                  label: 'Koreksi pengukuran',
                  kind: PillButtonKind.secondary,
                  onPressed: busy
                      ? null
                      : () =>
                            context.push('${Routes.glucose}/${record.id}/edit'),
                ),
              const SizedBox(height: 12),
              PillButton(
                label: record.archived
                    ? 'Pulihkan catatan'
                    : 'Arsipkan catatan',
                kind: PillButtonKind.secondary,
                loading: busy,
                onPressed: () => archive(record),
              ),
              const SizedBox(height: 24),
              Text('Riwayat koreksi', style: AppTypography.heading),
              ref
                  .watch(glucoseRevisionsProvider(record.id))
                  .when(
                    skipLoadingOnRefresh: false,
                    skipLoadingOnReload: false,
                    loading: () => const SkeletonList(rows: 1),
                    error: (e, _) => HealthError(
                      error: e,
                      retry: () =>
                          ref.invalidate(glucoseRevisionsProvider(record.id)),
                    ),
                    data: (items) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (items.isEmpty) const Text('Belum ada koreksi.'),
                        for (final item in items)
                          ExpansionTile(
                            title: Text(
                              'Versi ${item['version']} · ${item['reason']}',
                            ),
                            subtitle: Text(item['createdAt'] as String),
                            children: [
                              Text(
                                'Nilai sebelumnya: ${item['snapshot']['originalValue']} ${item['snapshot']['originalUnit']}\nWaktu sebelumnya: ${item['snapshot']['measuredAt']}',
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
              const SizedBox(height: 24),
              PillButton(
                label: 'Lihat riwayat glukosa',
                kind: PillButtonKind.secondary,
                onPressed: () => context.go(Routes.glucose),
              ),
            ],
          );
        },
      );
}
