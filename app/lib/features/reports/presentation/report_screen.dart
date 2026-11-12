import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/a11y/announce.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/choice_chips.dart';
import '../../../core/widgets/form_kit.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';

const reportCategories = {
  'bug': 'Masalah aplikasi',
  'adverse_event': 'Kejadian tidak diinginkan',
  'privacy': 'Privasi atau data',
  'other': 'Lainnya',
};

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});
  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  final message = TextEditingController();
  String category = 'bug';
  bool contactOk = false, busy = false;
  String? error, done;

  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (message.text.trim().length < 5) {
      setState(() => error = 'Tuliskan minimal satu kalimat singkat.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await ref
          .read(apiClientProvider)
          .post(
            '/api/me/reports',
            body: {
              'category': category,
              'message': message.text.trim(),
              'contactOk': contactOk,
              'appVersion': AppConfig.appVersion,
            },
          );
      if (!mounted) return;
      final text =
          r.object['message'] as String? ??
          'Terima kasih. Laporanmu tersimpan.';
      setState(() => done = text);
      announce(context, text);
    } catch (e) {
      if (mounted) setState(() => error = messageFor(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
    title: 'Laporkan masalah',
    bottom: done != null
        ? null
        : SaveBar(
            button: PillButton(
              label: 'Kirim laporan',
              loading: busy,
              onPressed: submit,
            ),
          ),
    children: [
      if (done != null) ...[
        InfoCard(title: 'Laporan terkirim', text: done!),
        const SizedBox(height: AppSpacing.md),
        PillButton(label: 'Selesai', onPressed: () => context.pop()),
      ] else ...[
        const InfoCard(
          tone: InfoTone.warning,
          title: 'Dalam keadaan darurat',
          text:
              'Laporan ini tidak dipantau setiap saat. Bila kamu merasa sangat tidak sehat sekarang, hubungi layanan darurat 119 atau fasilitas kesehatan terdekat.',
        ),
        FormSection(
          title: 'Jenis laporan',
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final e in reportCategories.entries)
                  PillChip(
                    label: e.value,
                    selected: category == e.key,
                    onTap: busy ? null : () => setState(() => category = e.key),
                  ),
              ],
            ),
            if (category == 'adverse_event')
              const FormNote(
                'Ceritakan apa yang terjadi, kapan, dan fitur mana yang sedang kamu pakai.',
              ),
          ],
        ),
        FormSection(
          title: 'Ceritakan',
          children: [
            TextField(
              controller: message,
              maxLength: 2000,
              minLines: 4,
              maxLines: 10,
              enabled: !busy,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Apa yang terjadi?',
                helperText: 'Tulis hanya yang perlu. Jangan tulis kata sandi.',
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: contactOk,
              onChanged: busy ? null : (v) => setState(() => contactOk = v!),
              title: const Text('Boleh dihubungi lewat surel akun'),
              subtitle: Text(
                'Bila tidak dicentang, surelmu tidak ikut dikirim.',
                style: AppTypography.caption,
              ),
            ),
          ],
        ),
        if (error != null) ErrorBanner(error!),
      ],
    ],
  );
}
