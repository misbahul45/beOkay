import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/error_messages.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/pill_button.dart';
import '../../auth/application/auth_controller.dart';
import '../application/activity_controller.dart';
import '../data/device_activity_source.dart';

final activityImportRepositoryProvider = Provider<ActivityImportRepository>((
  ref,
) {
  final auth = ref.watch(authControllerProvider);
  final id = auth is AuthAuthenticated ? auth.user.id : null;
  return ActivityImportRepository(
    ref.watch(apiClientProvider),
    isCurrentAccount: () {
      if (!ref.mounted) return false;
      final current = ref.read(authControllerProvider);
      return id != null &&
          current is AuthAuthenticated &&
          current.user.id == id;
    },
  );
});

/// Impor sesi olahraga dari Health Connect (30 hari terakhir). Hanya dijalankan saat pengguna menekan tombol.
/// Sesi yang bertabrakan waktu dengan catatan lain tidak dihitung sampai diperiksa.
class DeviceImportSection extends ConsumerStatefulWidget {
  const DeviceImportSection({super.key});
  @override
  ConsumerState<DeviceImportSection> createState() =>
      _DeviceImportSectionState();
}

class _DeviceImportSectionState extends ConsumerState<DeviceImportSection> {
  bool busy = false;
  String? message;
  bool failed = false;

  void _fail(String m) => setState(() {
    failed = true;
    message = m;
  });

  Future<void> run(DeviceActivitySource source) async {
    setState(() {
      busy = true;
      message = null;
      failed = false;
    });
    try {
      final status = await source.status();
      if (status == DeviceSourceStatus.notInstalled) {
        _fail(
          '${source.displayName} belum terpasang atau belum aktif di perangkat ini.',
        );
        return;
      }
      if (status == DeviceSourceStatus.unsupportedPlatform) {
        _fail('Impor belum didukung di perangkat ini.');
        return;
      }
      if (status == DeviceSourceStatus.needsPermission &&
          !await source.requestAccess()) {
        _fail('Izin membaca sesi olahraga belum diberikan.');
        return;
      }
      final now = DateTime.now();
      final sessions = await source.readWorkouts(
        from: now.subtract(const Duration(days: 30)),
        to: now,
      );
      if (sessions.isEmpty) {
        setState(
          () => message =
              'Tidak ada sesi olahraga di ${source.displayName} dalam 30 hari terakhir.',
        );
        return;
      }
      final r = await ref
          .read(activityImportRepositoryProvider)
          .send(source.sourceKey, sessions);
      ref.invalidate(activityPageProvider);
      ref.invalidate(activityDayProvider);
      setState(
        () => message =
            'Dibaca ${r.read} sesi: ${r.created} ditambahkan, ${r.needsReview} perlu diperiksa (bertabrakan waktu), ${r.duplicate} sudah ada${r.rejected > 0 ? ', ${r.rejected} ditolak' : ''}.',
      );
    } catch (e) {
      if (mounted) _fail(messageFor(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(deviceActivitySourceProvider);
    if (source == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PillButton(
          label: 'Impor dari ${source.displayName}',
          icon: Icons.watch_outlined,
          kind: PillButtonKind.secondary,
          loading: busy,
          onPressed: () => run(source),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Hanya membaca sesi olahraga 30 hari terakhir. Sesi yang sama tidak ditambahkan dua kali.',
          style: AppTypography.caption,
        ),
        if (message != null) ...[
          const SizedBox(height: AppSpacing.xs),
          InfoCard(
            tone: failed ? InfoTone.error : InfoTone.neutral,
            text: message!,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}
