import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/a11y/announce.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/settings_group.dart';
import '../../clinical/application/clinical_controller.dart';
import '../../today/application/today_controller.dart';
import '../application/devices_controller.dart';
import '../data/health_signals.dart';
import 'device_status_section.dart';

class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});
  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  bool busy = false;
  String? message;
  bool failed = false;

  Future<void> toggle(SignalType t, bool on) async {
    final source = ref.read(healthSignalsSourceProvider);
    setState(() {
      busy = true;
      message = null;
      failed = false;
    });
    try {
      if (on && source != null) {
        if (!await source.available()) {
          setState(() {
            failed = true;
            message =
                'Health Connect belum terpasang atau belum aktif di perangkat ini.';
          });
          return;
        }
        if (!await source.hasAccess(t) && !await source.requestAccess(t)) {
          setState(() {
            failed = true;
            message =
                'Izin ${t.label.toLowerCase()} belum diberikan di Health Connect.';
          });
          return;
        }
      }
      await ref.read(deviceImportRepositoryProvider).setPreference(t, on);
      ref.invalidate(devicePreferencesProvider);
      if (mounted) {
        announce(context, '${t.label} ${on ? 'dinyalakan' : 'dimatikan'}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          failed = true;
          message = messageFor(e);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> sync(Map<SignalType, bool> prefs) async {
    final source = ref.read(healthSignalsSourceProvider);
    if (source == null) return;
    setState(() {
      busy = true;
      message = null;
      failed = false;
    });
    try {
      final r = await syncDeviceSignals(
        source,
        ref.read(deviceImportRepositoryProvider),
        prefs,
      );
      ref.invalidate(stepsSummaryProvider);
      ref.invalidate(deviceStatusProvider);
      ref.invalidate(todayProvider);
      ref.invalidate(clinicalSummaryProvider);
      final text = r.total == 0
          ? 'Tidak ada data baru dari Health Connect.'
          : 'Diperbarui: ${r.steps} hari langkah, ${r.weights} berat badan, ${r.glucose} glukosa, ${r.sleep} sesi tidur.';
      setState(() => message = text);
      if (mounted) announce(context, text);
    } catch (e) {
      if (mounted) {
        setState(() {
          failed = true;
          message = messageFor(e);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(healthSignalsSourceProvider);
    final prefs = ref.watch(devicePreferencesProvider);
    return PageScaffold(
      title: 'Data dari perangkat',
      children: [
        const InfoCard(
          tone: InfoTone.neutral,
          text:
              'Setiap jenis data hanya dibaca bila kamu menyalakannya di sini dan memberi izin di Health Connect. beOkay tidak menulis apa pun ke Health Connect. Data perangkat ditandai "dari perangkat" dan bisa diarsipkan.',
        ),
        const SizedBox(height: AppSpacing.md),
        const DeviceStatusSection(),
        if (source == null)
          const InfoCard(
            text:
                'Impor data perangkat hanya tersedia di Android dengan Health Connect.',
          )
        else
          prefs.when(
            loading: () => const SkeletonList(rows: 3),
            error: (e, _) => ErrorState(
              error: e,
              onRetry: () => ref.invalidate(devicePreferencesProvider),
            ),
            data: (p) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingsGroup(
                  title: 'Jenis data',
                  children: [
                    for (final t in SignalType.values.where(
                      (t) => t != SignalType.workouts,
                    ))
                      SettingsRow(
                        title: t.label,
                        subtitle: t.detail,
                        trailing: Switch(
                          value: p[t] == true,
                          onChanged: busy ? null : (v) => toggle(t, v),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Sesi olahraga diimpor dari halaman Aktivitas.',
                  style: AppTypography.caption,
                ),
                const SizedBox(height: AppSpacing.md),
                PillButton(
                  label: 'Sinkronkan 14 hari terakhir',
                  icon: Icons.sync,
                  loading: busy,
                  onPressed: p.values.any((v) => v) ? () => sync(p) : null,
                ),
              ],
            ),
          ),
        if (message != null) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoCard(
            tone: failed ? InfoTone.error : InfoTone.info,
            text: message!,
          ),
        ],
      ],
    );
  }
}
