import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/error_messages.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/info_card.dart';
import '../../consent/application/consent_controller.dart';
import '../application/devices_controller.dart';

String _ago(DateTime? at) {
  if (at == null) return 'belum pernah sinkron';
  final d = DateTime.now().difference(at.toLocal());
  if (d.inMinutes < 60) return 'sinkron ${d.inMinutes.clamp(1, 59)} menit lalu';
  if (d.inHours < 48) return 'sinkron ${d.inHours} jam lalu';
  return 'sinkron ${d.inDays} hari lalu';
}

class DeviceStatusSection extends ConsumerStatefulWidget {
  const DeviceStatusSection({super.key});

  @override
  ConsumerState<DeviceStatusSection> createState() =>
      _DeviceStatusSectionState();
}

class _DeviceStatusSectionState extends ConsumerState<DeviceStatusSection> {
  bool _busy = false;

  Future<void> _setCoaching(bool on) async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(consentRepositoryProvider);
      if (on) {
        final policy = await ref.read(consentPolicyProvider.future);
        await repo.grant(
          policyVersion: policy.version,
          purposes: const ['device_data_coaching'],
          source: 'settings',
        );
      } else {
        await repo.withdraw(const ['device_data_coaching']);
      }
      ref.invalidate(deviceStatusProvider);
      ref.invalidate(consentControllerProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(deviceStatusProvider).value;
    if (status == null) return const SizedBox.shrink();
    Widget card(String overline, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(overline, style: AppTypography.overline),
              ),
              const SizedBox(height: AppSpacing.xs),
              ...children,
            ],
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card('14 HARI TERAKHIR', [
          for (final s in status.signals)
            Semantics(
              label:
                  '${s.label}: data ada ${s.observedDays} dari ${s.days} hari. ${_ago(status.lastSync[s.signal])}.${s.conflicts > 0 ? ' ${s.conflicts} hari dari dua perangkat.' : ''}',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(s.label, style: AppTypography.bodyStrong),
                        ),
                        Text(
                          '${(s.coverage * 100).round()}%',
                          style: AppTypography.secondaryStrong,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: s.coverage.clamp(0, 1),
                        minHeight: 8,
                        color: s.conflicts > 0
                            ? AppColors.sparkAmber
                            : AppColors.brand,
                        backgroundColor: AppColors.border,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        '${s.observedDays} dari ${s.days} hari',
                        _ago(status.lastSync[s.signal]),
                        if (s.conflicts > 0)
                          '${s.conflicts} hari dari dua perangkat',
                      ].join(' · '),
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
            ),
        ]),
        if (status.origins.isNotEmpty)
          card('ASAL DATA', [
            Text(
              status.origins.map(originLabel).join(' · '),
              style: AppTypography.body,
            ),
            Text(
              'Waktu tidur yang tumpang tindih dari dua perangkat hanya dihitung sekali.',
              style: AppTypography.caption,
            ),
          ]),
        card('UNTUK RENCANA KECIL', [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: status.usedForCoaching,
            onChanged: _busy ? null : _setCoaching,
            title: Text(
              'Pakai data perangkat untuk saran',
              style: AppTypography.bodyStrong,
            ),
            subtitle: Text(
              'Opsional. Bila mati, saran hanya memakai catatan yang kamu masukkan sendiri.',
              style: AppTypography.caption,
            ),
          ),
        ]),
        InfoCard(tone: InfoTone.neutral, text: status.notice),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}
