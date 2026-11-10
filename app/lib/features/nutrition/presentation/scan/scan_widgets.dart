import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// Penanda asal data. Selalu tampil di layar hasil agar pengguna tahu seberapa jauh angka bisa dipercaya.
class ProvenanceChip extends StatelessWidget {
  const ProvenanceChip(this.text, {super.key, this.positive = false});
  final String text;
  final bool positive;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: positive
            ? AppColors.infoBackground
            : AppColors.warningBackground,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text,
        style: AppTypography.caption.copyWith(
          color: positive
              ? AppColors.infoForeground
              : AppColors.warningForeground,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

/// Kartu pilihan metode pencatatan (satu ikon + judul + penjelasan).
class MethodCard extends StatelessWidget {
  const MethodCard({
    super.key,
    required this.icon,
    required this.tint,
    required this.ink,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final Color tint, ink;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$title. $subtitle',
    excludeSemantics: true,
    onTap: onTap,
    child: Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: AppRadius.cardRadius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                child: Icon(icon, color: ink),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.bodyStrong),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppTypography.secondary),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Dialog persetujuan sebelum foto dikirim keluar perangkat. Selalu ditanyakan; tidak diingat.
Future<bool> confirmImageUpload(
  BuildContext context, {
  required String subject,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Kirim foto untuk dibaca?'),
        content: Text(
          'Foto $subject dikirim ke layanan pembaca gambar (Mistral) hanya untuk dibaca, lalu dihapus. '
          'Hindari wajah atau dokumen pribadi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kirim foto'),
          ),
        ],
      ),
    ) ??
    false;

/// Menjalankan pekerjaan jaringan dengan dialog progres yang tidak bisa ditutup sembarangan.
Future<T> runWithProgress<T>(
  BuildContext context,
  String label,
  Future<T> Function() job,
) async {
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              height: 28,
              width: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    ),
  );
  try {
    return await job();
  } finally {
    nav.pop();
  }
}
