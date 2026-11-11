import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../auth/application/auth_controller.dart';
import '../../export/presentation/export_section.dart';

const deletedItems = [
  'Profil, profil kesehatan, dan pengaturan',
  'Semua catatan makan, glukosa, aktivitas, obat, dan tujuan',
  'Preferensi makanan, pengingat, dan perangkat notifikasi',
  'Riwayat asisten, rencana, dan hal yang dipelajari asisten',
  'Keanggotaan komunitas, alias, dan skor tantangan',
  'Riwayat persetujuan dan semua sesi login',
];

class PrivacyDataScreen extends StatelessWidget {
  const PrivacyDataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Privasi & data',
      children: [
        const ExportSection(),
        const SizedBox(height: AppSpacing.xl),
        Semantics(
          header: true,
          child: Text('Hapus akun', style: AppTypography.title),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Akun dan semua catatanmu dihapus permanen dan tidak bisa dikembalikan. Unduh datamu dulu bila ingin menyimpannya.',
          style: AppTypography.secondary,
        ),
        const SizedBox(height: AppSpacing.sm),
        PillButton(
          label: 'Hapus akun dan data',
          icon: Icons.delete_outline_rounded,
          kind: PillButtonKind.secondary,
          onPressed: () => context.push(Routes.deleteAccount),
        ),
      ],
    );
  }
}

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _ready =>
      _password.text.isNotEmpty &&
      _confirm.text.trim().toUpperCase() == 'HAPUS';

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (!_ready || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .deleteAccount(_password.text);
      messenger.showSnackBar(
        const SnackBar(content: Text('Akun dan datamu sudah dihapus.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (e.code) {
          'INVALID_PASSWORD' => 'Kata sandi tidak cocok.',
          'DELETE_RATE_LIMITED' =>
            'Terlalu banyak percobaan. Coba lagi dalam 15 menit.',
          _ => messageFor(e),
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Hapus akun',
      bottom: PillButton(
        label: 'Hapus permanen',
        loading: _busy,
        kind: PillButtonKind.danger,
        onPressed: _ready ? _delete : null,
      ),
      children: [
        Text('Yang akan dihapus', style: AppTypography.title),
        const SizedBox(height: AppSpacing.xs),
        for (final item in deletedItems)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.remove_circle_outline_rounded,
                  size: 18,
                  color: AppColors.errorForeground,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: Text(item, style: AppTypography.body)),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        InfoCard(
          tone: InfoTone.warning,
          text:
              'Tindakan ini tidak bisa dibatalkan. Catatan audit tanpa identitas tetap disimpan untuk keamanan.',
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          label: 'Kata sandi',
          controller: _password,
          obscure: true,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: 'Ketik HAPUS untuk konfirmasi',
          controller: _confirm,
          onChanged: (_) => setState(() {}),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoCard(tone: InfoTone.error, text: _error!),
        ],
      ],
    );
  }
}
