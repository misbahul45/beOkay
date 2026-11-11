import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/format/formatters.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/detail_kit.dart';
import '../../../core/widgets/domain_style.dart';
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
              DetailHero(
                style: DomainStyle.activity,
                eyebrow:
                    activityTypes[record.activityType] ?? record.activityType,
                value: '${record.durationMinutes}',
                unit: 'menit',
                archived: record.archived,
                chips: [
                  '${record.localDate} · ${record.localTime}–${record.endLocalTime}',
                  record.qualityLabel,
                ],
              ),
              DetailSection(
                title: 'Rincian',
                children: [
                  DetailRow(
                    'Mulai',
                    '${record.localDate} · ${record.localTime}',
                  ),
                  DetailRow(
                    'Selesai',
                    '${record.endLocalDate} · ${record.endLocalTime}',
                  ),
                  DetailRow(
                    'Jarak',
                    record.distanceKm == null
                        ? 'Belum diketahui'
                        : '${record.distanceKm} km',
                  ),
                  DetailRow(
                    'Langkah',
                    record.steps == null
                        ? 'Belum diketahui'
                        : '${record.steps}',
                  ),
                  DetailRow(
                    'Intensitas',
                    activityIntensities[record.reportedIntensity] ??
                        record.reportedIntensity,
                  ),
                  const DetailRow('Sumber', 'Manual'),
                  DetailRow('Zona waktu', record.timezone),
                  if (record.version > 1 || record.archived)
                    DetailRow(
                      'Versi',
                      revisionLabel(record.version, archived: record.archived),
                    ),
                ],
              ),
              if (record.notes != null)
                DetailSection(
                  title: 'Catatan',
                  children: [Text(record.notes!, style: AppTypography.body)],
                ),
              DetailActions(
                children: [
                  if (!record.archived)
                    PillButton(
                      label: 'Koreksi aktivitas',
                      icon: Icons.edit_outlined,
                      kind: PillButtonKind.secondary,
                      expand: false,
                      onPressed: busy
                          ? null
                          : () => context.push(
                              '${Routes.activities}/${record.id}/edit',
                            ),
                    ),
                  PillButton(
                    label: record.archived
                        ? 'Pulihkan catatan'
                        : 'Arsipkan catatan',
                    icon: record.archived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                    kind: PillButtonKind.secondary,
                    expand: false,
                    loading: busy,
                    onPressed: () => archive(record),
                  ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                ErrorBanner(error!),
                TextButton(
                  onPressed: () => ref.invalidate(activityProvider(record.id)),
                  child: const Text('Muat ulang catatan'),
                ),
              ],
              DetailSection(
                title: 'Riwayat koreksi',
                children: [
                  ref
                      .watch(activityRevisionsProvider(record.id))
                      .when(
                        skipLoadingOnRefresh: false,
                        skipLoadingOnReload: false,
                        loading: () => const SkeletonList(rows: 1),
                        error: (e, _) => HealthError(
                          error: e,
                          retry: () => ref.invalidate(
                            activityRevisionsProvider(record.id),
                          ),
                        ),
                        data: (items) => RevisionTimeline(
                          entries: [
                            for (final item in items)
                              RevisionEntry(
                                version: item['version'] as int,
                                reason: '${item['reason']}',
                                createdAt: '${item['createdAt']}',
                                before:
                                    'Sebelumnya: ${item['snapshot']['durationMinutes']} menit · ${friendlyStamp('${item['snapshot']['startedAt']}')}',
                              ),
                          ],
                        ),
                      ),
                ],
              ),
              DetailSection(
                title: 'Provenansi',
                children: [
                  DetailRow(
                    'Mulai',
                    friendlyStamp(record.startedAt.toIso8601String()),
                  ),
                  DetailRow(
                    'Selesai',
                    friendlyStamp(record.endedAt.toIso8601String()),
                  ),
                  DetailRow('Dicatat', friendlyStamp('${record.recordedAt}')),
                  DetailRow(
                    'Diterima server',
                    friendlyStamp('${record.receivedAt}'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              PillButton(
                label: 'Lihat riwayat aktivitas',
                kind: PillButtonKind.ghost,
                onPressed: () => context.go(Routes.activities),
              ),
            ],
          );
        },
      );
}
