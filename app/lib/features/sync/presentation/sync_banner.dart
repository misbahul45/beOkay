import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/a11y/announce.dart';
import '../../../core/offline/sync_controller.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// Satu baris di atas layar utama, hanya muncul bila ada catatan yang belum terkirim atau perlu ditinjau.
class SyncBanner extends ConsumerWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(syncControllerProvider, (prev, next) {
      if (prev == null) return;
      if (prev.pending > 0 &&
          next.pending == 0 &&
          next.needsAttention == 0 &&
          !next.running) {
        announce(context, 'Semua catatan sudah terkirim');
      } else if (next.needsAttention > prev.needsAttention) {
        announce(context, '${next.needsAttention} catatan perlu ditinjau');
      }
    });
    final s = ref.watch(syncControllerProvider);
    if (s.items.isEmpty) return const SizedBox.shrink();
    final attention = s.needsAttention > 0;
    final text = attention
        ? '${s.needsAttention} catatan perlu ditinjau'
        : s.running
        ? 'Mengirim ${s.pending} catatan…'
        : s.blockedByConsent
        ? 'Pengiriman dihentikan: persetujuan diperlukan'
        : '${s.pending} catatan tersimpan di perangkat, menunggu dikirim';
    return Material(
      color: attention ? AppColors.warningBackground : AppColors.infoBackground,
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: () => context.push(Routes.sync),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.page,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Icon(
                    attention
                        ? Icons.rule_rounded
                        : Icons.cloud_upload_outlined,
                    size: 20,
                    color: attention
                        ? AppColors.warningForeground
                        : AppColors.infoForeground,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(text, style: AppTypography.secondary),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
