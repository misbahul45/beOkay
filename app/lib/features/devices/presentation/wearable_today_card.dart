import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/soft_card.dart';
import '../application/devices_controller.dart';
import '../domain/heart_rate.dart';

String _duration(int minutes) => '${minutes ~/ 60}j ${minutes % 60}m';

class WearableTodayCard extends ConsumerWidget {
  const WearableTodayCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(deviceTodayProvider).value;
    if (today == null || !today.anyEnabled) return const SizedBox.shrink();
    final rows = <Widget>[
      if (today.steps.availability != MetricAvailability.notEnabled)
        _Row(
          icon: Icons.directions_walk_rounded,
          label: 'Langkah',
          metric: today.steps,
          value: (v) => '${v['steps']} langkah',
          caption: (v) => v['date'] == null ? null : 'per ${v['date']}',
          onTap: () => context.push(Routes.devices),
        ),
      if (today.heartRate.availability != MetricAvailability.notEnabled)
        _Row(
          icon: Icons.monitor_heart_outlined,
          label: 'Detak jantung',
          metric: today.heartRate,
          value: (v) => '${v['bpm']} bpm',
          caption: (v) => v['restingBpm'] == null
              ? 'Rata-rata 5 menit terakhir'
              : 'Istirahat ${v['restingBpm']} bpm',
          onTap: () => context.push(Routes.heartRate),
        ),
      if (today.sleep.availability != MetricAvailability.notEnabled)
        _Row(
          icon: Icons.bedtime_outlined,
          label: 'Tidur terakhir',
          metric: today.sleep,
          value: (v) => _duration((v['durationMinutes'] as num).toInt()),
          caption: (_) => null,
          onTap: () => context.push(Routes.devices),
        ),
      if (today.activity.availability != MetricAvailability.notEnabled)
        _Row(
          icon: Icons.fitness_center_outlined,
          label: 'Aktivitas dari perangkat',
          metric: today.activity,
          value: (v) => '${v['minutes']} menit',
          caption: (v) => '${v['sessions']} sesi hari ini',
          onTap: () => context.push(Routes.devices),
        ),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    final simulated =
        today.steps.simulated ||
        today.heartRate.simulated ||
        today.sleep.simulated;
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'DARI PERANGKAT',
                      style: AppTypography.overline,
                    ),
                  ),
                ),
                if (simulated)
                  const StatusBadge(
                    label: 'DATA SIMULASI',
                    tone: InfoTone.warning,
                  ),
              ],
            ),
          ),
          ...rows,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.metric,
    required this.value,
    required this.caption,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final DeviceMetricToday metric;
  final String Function(Map<String, dynamic>) value;
  final String? Function(Map<String, dynamic>) caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final v = metric.value;
    final has =
        v != null &&
        (metric.availability == MetricAvailability.hasData ||
            metric.availability == MetricAvailability.staleData);
    final text = has
        ? value(v)
        : switch (metric.availability) {
            MetricAvailability.permissionRequired =>
              'Perlu izin Health Connect',
            _ => 'Belum ada data',
          };
    final sub = has ? caption(v) : null;
    final stale = metric.availability == MetricAvailability.staleData;
    return Semantics(
      button: true,
      label: [label, text, ?sub, if (stale) 'data sudah lama'].join('. '),
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 8,
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppColors.textPrimary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: AppTypography.secondary),
                      Text(
                        text,
                        style: has
                            ? AppTypography.bodyStrong
                            : AppTypography.body,
                      ),
                      if (sub != null) Text(sub, style: AppTypography.caption),
                    ],
                  ),
                ),
                if (stale)
                  const StatusBadge(
                    label: 'Sudah lama',
                    tone: InfoTone.warning,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
