import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../application/intervention_controller.dart';
import '../data/intervention_repository.dart';

/// Satu saran singkat di Beranda. Hanya tampil bila server memutuskan ada; setiap tombol punya akibat nyata di server.
class InterventionCard extends ConsumerWidget {
  const InterventionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items =
        ref.watch(openInterventionsProvider).value ?? const <Intervention>[];
    if (items.isEmpty) return const SizedBox.shrink();
    final item = items.first;
    Future<void> send(String kind, {int? snooze}) async {
      try {
        await ref
            .read(interventionRepositoryProvider)
            .respond(item.id, kind, snoozeMinutes: snooze);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Belum bisa disimpan. Coba lagi.')),
          );
        }
        return;
      }
      ref.invalidate(openInterventionsProvider);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Material(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(item.title, style: AppTypography.bodyStrong),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Lainnya',
                    onSelected: (v) async {
                      if (v == 'PAUSE') {
                        try {
                          await ref
                              .read(interventionRepositoryProvider)
                              .pauseForHours(168);
                          ref.invalidate(openInterventionsProvider);
                        } catch (_) {}
                      } else {
                        await send(v);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'ALREADY_DONE',
                        child: Text('Sudah dilakukan'),
                      ),
                      PopupMenuItem(
                        value: 'NOT_USEFUL',
                        child: Text('Tidak cocok'),
                      ),
                      PopupMenuItem(
                        value: 'TOO_FREQUENT',
                        child: Text('Terlalu sering'),
                      ),
                      PopupMenuItem(
                        value: 'PAUSE',
                        child: Text('Jeda 1 minggu'),
                      ),
                    ],
                  ),
                ],
              ),
              Text(item.body, style: AppTypography.secondary),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: () async {
                      await send('OPENED');
                      if (!context.mounted) return;
                      context.push(switch (item.action) {
                        'OPEN_COACH' => Routes.coach,
                        'OPEN_INSIGHTS' => Routes.insights,
                        _ => Routes.goals,
                      });
                    },
                    child: const Text('Buka'),
                  ),
                  TextButton(
                    onPressed: () => send('NOT_NOW', snooze: 120),
                    child: const Text('Nanti'),
                  ),
                  TextButton(
                    onPressed: () => send('STOP_THIS_TYPE'),
                    child: const Text('Jangan lagi'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
