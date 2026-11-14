import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/a11y/announce.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/settings_group.dart';
import '../../../core/widgets/soft_card.dart';
import '../application/devices_controller.dart';
import '../data/health_connect_source.dart';
import '../data/health_source.dart';
import '../domain/connection_state.dart';
import '../domain/device_status.dart';
import 'device_status_section.dart';
import 'simulation_panel.dart';

String agoText(DateTime? at) {
  if (at == null) return 'belum pernah';
  final d = DateTime.now().difference(at.toLocal());
  if (d.inMinutes < 1) return 'baru saja';
  if (d.inMinutes < 60) return '${d.inMinutes} menit lalu';
  if (d.inHours < 48) return '${d.inHours} jam lalu';
  return '${d.inDays} hari lalu';
}

class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});
  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(deviceConnectionProvider.notifier).refresh();
    });
  }

  Future<void> _stop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hentikan sinkronisasi?'),
        content: const Text(
          'Semua jenis data dimatikan dan tidak ada data baru yang dibaca. Data yang sudah masuk tetap tersimpan dan bisa kamu hapus dari Privasi & data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Hentikan'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(deviceConnectionProvider.notifier).stopAll();
    }
  }

  Future<void> _manage() async {
    final opened = await openHealthConnectSettings();
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Buka Health Connect dari pengaturan Android untuk mengatur izin.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(deviceConnectionProvider);
    final controller = ref.read(deviceConnectionProvider.notifier);
    ref.listen(deviceConnectionProvider.select((v) => v.message), (_, m) {
      if (m != null && mounted) announce(context, m);
    });
    final source = ref.watch(healthDataSourceProvider);
    final enabledAny = view.enabled.isNotEmpty;
    return PageScaffold(
      title: 'Perangkat & Kesehatan',
      onRefresh: controller.refresh,
      children: [
        const SimulationBanner(),
        const InfoCard(
          tone: InfoTone.neutral,
          text:
              'beOkay hanya membaca dari Health Connect dan tidak menulis apa pun ke sana. Setiap jenis data dibaca hanya bila kamu menyalakannya di sini dan memberi izin di Health Connect.',
        ),
        const SizedBox(height: AppSpacing.md),
        if (source == null) ...[
          const InfoCard(
            text:
                'Impor data perangkat hanya tersedia di Android dengan Health Connect.',
          ),
          const SizedBox(height: AppSpacing.md),
          _SourcesCard(status: ref.watch(deviceStatusProvider).value),
          const SizedBox(height: AppSpacing.md),
          const DeviceStatusSection(),
        ] else if (view.loading)
          const SkeletonList(rows: 3)
        else ...[
          _ConnectionCard(
            view: view,
            onSync: enabledAny && !view.syncing
                ? () => controller.syncNow()
                : null,
            onManage: _manage,
          ),
          const SizedBox(height: AppSpacing.md),
          _SourcesCard(
            status: view.status ?? ref.watch(deviceStatusProvider).value,
          ),
          const SizedBox(height: AppSpacing.md),
          _MetricsGroup(view: view),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Belum didukung: ${unsupportedMetricLabels.join(', ')}.',
            style: AppTypography.caption,
          ),
          if (view.message != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              liveRegion: true,
              child: InfoCard(
                tone: view.failed ? InfoTone.error : InfoTone.info,
                text: view.message!,
                action: view.failed && enabledAny
                    ? TextButton(
                        onPressed: view.syncing
                            ? null
                            : () => controller.syncNow(),
                        child: const Text('Coba lagi'),
                      )
                    : null,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          const DeviceStatusSection(),
          if (view.enabled.contains(WearableMetric.heartRate) ||
              view.enabled.contains(WearableMetric.restingHeartRate)) ...[
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: Icons.monitor_heart_outlined,
                  title: 'Detak jantung',
                  subtitle: 'Rentang harian, istirahat, dan tren',
                  onTap: () => context.push(Routes.heartRate),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          SettingsGroup(
            title: 'Privasi',
            children: [
              SettingsRow(
                icon: Icons.health_and_safety_outlined,
                title: 'Kelola izin Health Connect',
                subtitle:
                    'Buka pengaturan sistem untuk mencabut atau memberi izin',
                onTap: _manage,
              ),
              SettingsRow(
                icon: Icons.folder_shared_outlined,
                title: 'Privasi & data',
                subtitle: 'Ekspor atau hapus data kesehatanmu',
                onTap: () => context.push(Routes.privacyData),
              ),
              SettingsRow(
                icon: Icons.stop_circle_outlined,
                title: 'Hentikan sinkronisasi',
                subtitle: 'Matikan semua jenis data sekaligus',
                destructive: true,
                onTap: enabledAny && !view.syncing ? _stop : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const SimulationPanel(),
        ],
      ],
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.view,
    required this.onSync,
    required this.onManage,
  });
  final DeviceConnectionView view;
  final VoidCallback? onSync;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final state = view.state;
    final status = view.status;
    final tone = switch (state) {
      DeviceConnectionState.dataAvailable => InfoTone.info,
      DeviceConnectionState.syncFailed ||
      DeviceConnectionState.syncStale ||
      DeviceConnectionState.notAuthorized => InfoTone.warning,
      _ => InfoTone.neutral,
    };
    final watch = status?.watch ?? WatchVerification.notVerified;
    final watchText = switch (watch) {
      WatchVerification.notVerified =>
        'Jam tangan: belum terverifikasi. Data di Health Connect tidak membuktikan ada jam tangan yang terpasang.',
      WatchVerification.sourceDetected =>
        'Jam tangan: sumber data menyatakan berasal dari jam tangan. Belum diuji dengan perangkat keras beOkay.',
      WatchVerification.hardwareVerified =>
        'Jam tangan: terverifikasi lewat uji perangkat keras.',
    };
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('HEALTH CONNECT', style: AppTypography.overline),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(state.title, style: AppTypography.title),
                ),
              ),
              if (view.syncing)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(state.explanation, style: AppTypography.secondary),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              StatusBadge(
                label: view.platform == HealthPlatformState.available
                    ? 'Health Connect tersedia'
                    : 'Health Connect belum tersedia',
                tone: view.platform == HealthPlatformState.available
                    ? tone
                    : InfoTone.warning,
              ),
              StatusBadge(
                label:
                    'Sinkron terakhir: ${agoText(view.lastSuccessAt ?? status?.lastSuccessfulSyncAt)}',
              ),
              const StatusBadge(label: 'Sinkron saat aplikasi dibuka'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(watchText, style: AppTypography.caption),
          if (status?.lastDataAt != null) ...[
            const SizedBox(height: 2),
            Text(
              'Pengukuran terakhir: ${agoText(status!.lastDataAt)}',
              style: AppTypography.caption,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          PillButton(
            label: 'Sinkronkan sekarang',
            icon: Icons.sync,
            kind: PillButtonKind.ink,
            loading: view.syncing,
            onPressed: onSync,
          ),
          const SizedBox(height: AppSpacing.xs),
          PillButton(
            label: 'Kelola izin Health Connect',
            kind: PillButtonKind.secondary,
            onPressed: onManage,
          ),
        ],
      ),
    );
  }
}

class _SourcesCard extends StatelessWidget {
  const _SourcesCard({required this.status});
  final DeviceStatus? status;

  @override
  Widget build(BuildContext context) {
    final apps = status?.sourceApplications ?? const <SourceApplication>[];
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ASAL DATA', style: AppTypography.overline),
          const SizedBox(height: AppSpacing.xs),
          if (apps.isEmpty && (status?.origins.isNotEmpty ?? false))
            Text(
              status!.origins.map(originLabel).join(' · '),
              style: AppTypography.body,
            )
          else if (apps.isEmpty)
            Text(
              'Belum ada sumber data. Data dari ponsel tetap bisa masuk tanpa jam tangan.',
              style: AppTypography.secondary,
            )
          else
            for (final a in apps)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      a.provenance == 'WATCH_RECORDED'
                          ? Icons.watch_outlined
                          : a.provenance == 'SIMULATED'
                          ? Icons.science_outlined
                          : Icons.smartphone_outlined,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        '${originLabel(a.dataOrigin)} · ${provenanceLabel(a.provenance)}',
                        style: AppTypography.body,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _MetricsGroup extends ConsumerWidget {
  const _MetricsGroup({required this.view});
  final DeviceConnectionView view;

  String _subtitle(WearableMetric m) {
    final on = view.prefs[m] == true;
    if (!on) return m.detail;
    final granted = view.granted.contains(m);
    final signal = switch (m) {
      WearableMetric.steps => 'steps',
      WearableMetric.heartRate => 'heart_rate',
      WearableMetric.sleep => 'sleep',
      WearableMetric.workouts => 'workouts',
      _ => null,
    };
    final s = signal == null
        ? null
        : view.status?.signals.where((x) => x.signal == signal).firstOrNull;
    final parts = [
      granted ? 'Izin diberikan' : 'Izin belum diberikan',
      if (s != null) '${s.observedDays} dari ${s.days} hari ada data',
      if (s != null && s.conflicts > 0) '${s.conflicts} hari perlu ditinjau',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(deviceConnectionProvider.notifier);
    return SettingsGroup(
      title: 'Jenis data',
      children: [
        for (final m in WearableMetric.values)
          SettingsRow(
            title: m.label,
            subtitle: _subtitle(m),
            trailing: Switch(
              value: view.prefs[m] == true,
              onChanged: view.syncing ? null : (v) => controller.toggle(m, v),
            ),
          ),
      ],
    );
  }
}
