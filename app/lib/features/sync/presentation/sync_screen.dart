import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/offline/offline_queue.dart';
import '../../../core/offline/sync_controller.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';

/// Antrean sinkronisasi: apa yang masih di perangkat, apa yang bentrok, dan pilihan pengguna.
class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  static String _stateLabel(QueueState s) => switch (s) {
    QueueState.savedLocal => 'Tersimpan di perangkat',
    QueueState.syncing => 'Mengirim',
    QueueState.syncFailed => 'Belum terkirim, akan dicoba lagi',
    QueueState.conflict => 'Berbeda dengan data tersimpan',
    QueueState.needsReview => 'Perlu ditinjau',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncControllerProvider);
    final ctl = ref.read(syncControllerProvider.notifier);
    return PageScaffold(
      title: 'Sinkronisasi',
      onBack: () =>
          context.canPop() ? context.pop() : context.go(Routes.profile),
      bottom: s.pending > 0
          ? PillButton(
              label: 'Kirim sekarang',
              icon: Icons.cloud_upload_outlined,
              onPressed: ctl.flush,
            )
          : null,
      children: [
        if (s.items.isEmpty)
          const EmptyState(
            icon: Icons.cloud_done_outlined,
            title: 'Semua tersinkron',
            message: 'Tidak ada catatan yang menunggu.',
          )
        else
          for (final o in s.items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Material(
                color: AppColors.surface,
                borderRadius: AppRadius.cardRadius,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o.isCorrection ? 'Koreksi · ${o.label}' : o.label,
                        style: AppTypography.bodyStrong,
                      ),
                      Text(
                        '${DateFormat('d MMM, HH:mm').format(o.createdAt.toLocal())} · ${_stateLabel(o.state)}',
                        style: AppTypography.secondary,
                      ),
                      if (o.errorMessage != null)
                        Text(o.errorMessage!, style: AppTypography.secondary),
                      Row(
                        children: [
                          if (o.state == QueueState.syncFailed ||
                              o.state == QueueState.savedLocal)
                            TextButton(
                              onPressed: () => ctl.retry(o.operationId),
                              child: const Text('Coba lagi'),
                            ),
                          if (o.state == QueueState.conflict ||
                              o.state == QueueState.needsReview ||
                              o.state == QueueState.syncFailed)
                            TextButton(
                              onPressed: () => ctl.discard(o.operationId),
                              child: const Text('Buang catatan ini'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
