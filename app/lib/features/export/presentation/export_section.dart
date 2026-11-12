import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_lock/app_lock.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/pill_button.dart';
import '../data/data_exporter.dart';

/// "Unduh data saya": berkas JSON berisi catatanmu sendiri. Tidak memuat kata sandi atau sesi.
class ExportSection extends ConsumerStatefulWidget {
  const ExportSection({super.key});
  @override
  ConsumerState<ExportSection> createState() => _ExportSectionState();
}

class _ExportSectionState extends ConsumerState<ExportSection> {
  bool busy = false;
  String? message;
  bool failed = false;

  Future<void> run() async {
    if (!await ref
        .read(appLockProvider.notifier)
        .confirmSensitive('Konfirmasi mengunduh datamu')) {
      return;
    }
    setState(() {
      busy = true;
      message = null;
      failed = false;
    });
    try {
      final outcome = await ref.read(dataExporterProvider).run();
      if (mounted) {
        setState(
          () => message =
              'Data siap dibagikan (${outcome.records} catatan). Simpan di tempat yang aman.',
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          failed = true;
          message = e.code == 'EXPORT_RATE_LIMITED'
              ? 'Terlalu sering mengunduh. Coba lagi dalam satu jam.'
              : messageFor(e);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          failed = true;
          message = 'Data tidak dapat dibagikan. Coba lagi.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> runFhir() async {
    if (!await ref
        .read(appLockProvider.notifier)
        .confirmSensitive('Konfirmasi mengunduh datamu')) {
      return;
    }
    setState(() {
      busy = true;
      message = null;
      failed = false;
    });
    try {
      final n = await ref.read(fhirExporterProvider)();
      if (mounted) {
        setState(
          () => message =
              'Berkas FHIR siap dibagikan (${n > 0 ? n - 1 : 0} pengukuran). Simpan di tempat yang aman.',
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          failed = true;
          message = e.code == 'EXPORT_RATE_LIMITED'
              ? 'Terlalu sering mengunduh. Coba lagi dalam satu jam.'
              : messageFor(e);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          failed = true;
          message = 'Data tidak dapat dibagikan. Coba lagi.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: AppSpacing.lg),
      Semantics(
        header: true,
        child: Text('Data saya', style: AppTypography.title),
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'Unduh salinan semua catatan yang tersimpan atas namamu. Kamu tetap bisa mengunduhnya meski persetujuan ditarik.',
        style: AppTypography.secondary,
      ),
      const SizedBox(height: AppSpacing.sm),
      PillButton(
        label: 'Unduh data saya',
        icon: Icons.download_rounded,
        kind: PillButtonKind.secondary,
        loading: busy,
        onPressed: run,
      ),
      const SizedBox(height: AppSpacing.xs),
      PillButton(
        label: 'Ekspor FHIR R4',
        icon: Icons.local_hospital_outlined,
        kind: PillButtonKind.secondary,
        loading: busy,
        onPressed: runFhir,
      ),
      if (message != null) ...[
        const SizedBox(height: AppSpacing.xs),
        InfoCard(
          tone: failed ? InfoTone.error : InfoTone.neutral,
          text: message!,
        ),
      ],
      const SizedBox(height: AppSpacing.xs),
      Text(
        'Berkas berisi data kesehatanmu. Ringkasan turunan, sesi, dan kata sandi tidak disertakan. FHIR adalah standar pertukaran data kesehatan yang dipakai SATUSEHAT; beOkay belum tersambung ke SATUSEHAT, berkas ini untuk kamu bawa sendiri.',
        style: AppTypography.caption,
      ),
    ],
  );
}
