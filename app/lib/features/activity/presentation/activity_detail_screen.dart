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
import '../application/activity_controller.dart';
import '../data/activity_models.dart';
import 'activity_form_screen.dart';

class ActivityDetailScreen extends ConsumerStatefulWidget {
  const ActivityDetailScreen({super.key, required this.id, this.edit = false});
  final String id;
  final bool edit;
  @override
  ConsumerState<ActivityDetailScreen> createState() => _ActivityDetailState();
}

class _ActivityDetailState extends ConsumerState<ActivityDetailScreen> {
  bool busy = false;
  String? error;
  Future<void> archive(ActivityRecord record) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => RecordReasonDialog(restoring: record.archived),
    );
    if (reason == null || !mounted) return;
    final repo = ref.read(activityRepositoryProvider);
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
      ref.invalidate(activityProvider(record.id));
      ref.invalidate(activityPageProvider);
      ref.invalidate(activityDayProvider);
      ref.invalidate(activityWeekProvider);
      ref.invalidate(todayProvider);
    } catch (e) {
      if (mounted) setState(() => error = messageFor(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(activityProvider(widget.id))
      .when(
        skipLoadingOnRefresh: false,
        skipLoadingOnReload: false,
        loading: () => const PageScaffold(
          title: 'Memuat aktivitas',
          children: [SkeletonList()],
        ),
        error: (e, _) => PageScaffold(
          title: 'Detail aktivitas',
          children: [
            HealthError(
              error: e,
              retry: () => ref.invalidate(activityProvider(widget.id)),
            ),
          ],
        ),
        data: (record) {
          if (widget.edit) {
            return ActivityFormScreen(
              key: ValueKey(record.version),
              initial: record,
            );
          }
          return PageScaffold(
            title: 'Detail aktivitas',
            onBack: () => context.canPop()
                ? context.pop()
                : context.go(Routes.activities),
            actions: [
              IconButton(
                tooltip: 'Beranda',
                onPressed: () => context.go(Routes.home),
                icon: const Icon(Icons.home_outlined),
              ),
            ],
            children: [
              Text(
                activityTypes[record.activityType] ?? record.activityType,
                style: AppTypography.headline,
              ),
              Text(
                '${record.durationMinutes} menit',
                style: AppTypography.heading,
              ),
              const SizedBox(height: 16),
              HealthCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mulai: ${record.localDate} · ${record.localTime}'),
                    Text(
                      'Selesai: ${record.endLocalDate} · ${record.endLocalTime}',
                    ),
                    Text(record.timezone),
                    const SizedBox(height: 12),
                    Text(
                      'Jarak: ${record.distanceKm == null ? 'Belum diketahui' : '${record.distanceKm} km'}',
                    ),
                    Text('Langkah: ${record.steps ?? 'Belum diketahui'}'),
                    Text(
                      'Intensitas: ${activityIntensities[record.reportedIntensity]}',
                    ),
                    const Text('Sumber: manual'),
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
                      title: const Text('Provenansi sesi'),
                      children: [
                        Text(
                          'Mulai (UTC): ${record.startedAt.toIso8601String()}\nSelesai (UTC): ${record.endedAt.toIso8601String()}\nDicatat: ${record.recordedAt}\nDiterima: ${record.receivedAt}',
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
                  onPressed: () => ref.invalidate(activityProvider(record.id)),
                  child: const Text('Muat ulang catatan'),
                ),
              ],
              if (!record.archived)
                PillButton(
                  label: 'Koreksi aktivitas',
                  kind: PillButtonKind.secondary,
                  onPressed: busy
                      ? null
                      : () => context.push(
                          '${Routes.activities}/${record.id}/edit',
                        ),
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
                  .watch(activityRevisionsProvider(record.id))
                  .when(
                    skipLoadingOnRefresh: false,
                    skipLoadingOnReload: false,
                    loading: () => const SkeletonList(rows: 1),
                    error: (e, _) => HealthError(
                      error: e,
                      retry: () =>
                          ref.invalidate(activityRevisionsProvider(record.id)),
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
                                'Durasi sebelumnya: ${item['snapshot']['durationMinutes']} menit\nMulai sebelumnya: ${item['snapshot']['startedAt']}',
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
              const SizedBox(height: 24),
              PillButton(
                label: 'Lihat riwayat aktivitas',
                kind: PillButtonKind.secondary,
                onPressed: () => context.go(Routes.activities),
              ),
            ],
          );
        },
      );
}
