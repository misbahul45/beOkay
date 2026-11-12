import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/a11y/announce.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/choice_chips.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../auth/application/auth_controller.dart';
import '../data/share_repository.dart';
import '../data/summary_pdf.dart';

final shareRepositoryProvider = Provider<ShareRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  final id = auth is AuthAuthenticated ? auth.user.id : null;
  return ShareRepository(
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

final summaryProvider = FutureProvider.autoDispose.family<ReportSummary, int>(
  (ref, days) => ref.watch(shareRepositoryProvider).summary(days),
);
final shareLinksProvider = FutureProvider.autoDispose<List<ShareLinkView>>(
  (ref) => ref.watch(shareRepositoryProvider).links(),
);

typedef PdfSharer = Future<void> Function(String path, String name);
final pdfSharerProvider = Provider<PdfSharer>(
  (ref) =>
      (path, name) => SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: 'application/pdf', name: name)],
          subject: name,
        ),
      ),
);

class SummaryReportEntry extends StatelessWidget {
  const SummaryReportEntry({super.key});
  @override
  Widget build(BuildContext context) => InfoCard(
    icon: Icons.picture_as_pdf_outlined,
    title: 'Ringkasan untuk kontrol',
    text:
        'Buat PDF 1–2 halaman atau tautan baca-saja berbatas waktu untuk dokter, perawat, atau petugas Prolanis.',
    action: PillButton(
      label: 'Buka ringkasan',
      kind: PillButtonKind.secondary,
      expand: false,
      onPressed: () => context.push(Routes.summaryReport),
    ),
  );
}

class SummaryReportScreen extends ConsumerStatefulWidget {
  const SummaryReportScreen({super.key});
  @override
  ConsumerState<SummaryReportScreen> createState() =>
      _SummaryReportScreenState();
}

class _SummaryReportScreenState extends ConsumerState<SummaryReportScreen> {
  int days = 30;
  int hours = 72;
  bool busy = false;
  ShareLinkView? created;

  Future<void> pdf(ReportSummary s) async {
    setState(() => busy = true);
    try {
      final bytes = await buildSummaryPdf(s);
      final dir = await getTemporaryDirectory();
      final name = 'beokay-ringkasan-${s.days}hari-${s.end}.pdf';
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes, flush: true);
      await ref.read(pdfSharerProvider)(file.path, name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> createLink() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Buat tautan baca-saja?'),
        content: Text(
          'Siapa pun yang memegang tautan ini bisa melihat ringkasan $days hari, ukuran terakhir, dan daftar obatmu selama ${hours ~/ 24 > 0 ? '${hours ~/ 24} hari' : '$hours jam'}. Kamu bisa mencabutnya kapan saja.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Buat tautan'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => busy = true);
    try {
      final link = await ref
          .read(shareRepositoryProvider)
          .create(periodDays: days, hours: hours);
      ref.invalidate(shareLinksProvider);
      setState(() => created = link);
      if (mounted) announce(context, 'Tautan dibuat');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> revoke(String id) async {
    try {
      await ref.read(shareRepositoryProvider).revoke(id);
      if (created?.id == id) setState(() => created = null);
      ref.invalidate(shareLinksProvider);
      if (mounted) announce(context, 'Tautan dicabut');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(messageFor(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(summaryProvider(days));
    final links = ref.watch(shareLinksProvider);
    final fmt = DateFormat('d MMM HH.mm', 'id_ID');
    return PageScaffold(
      title: 'Ringkasan untuk kontrol',
      children: [
        Text('Periode', style: AppTypography.bodyStrong),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (final d in [14, 30, 90])
              PillChip(
                label: '$d hari',
                selected: days == d,
                onTap: busy ? null : () => setState(() => days = d),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        summary.when(
          loading: () => const SkeletonList(rows: 3),
          error: (e, _) => ErrorState(
            error: e,
            onRetry: () => ref.invalidate(summaryProvider(days)),
          ),
          data: (s) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadius.cardRadius,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${s.start} – ${s.end}', style: AppTypography.caption),
                    const SizedBox(height: 4),
                    if (s.statistics.where((x) => x.ready).isEmpty)
                      Text(
                        'Belum cukup catatan pada periode ini.',
                        style: AppTypography.secondary,
                      )
                    else
                      for (final x
                          in s.statistics.where((x) => x.ready).take(6))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(x.label, style: AppTypography.body),
                              ),
                              Text(x.display, style: AppTypography.bodyStrong),
                            ],
                          ),
                        ),
                    const SizedBox(height: 6),
                    Text(s.disclaimer, style: AppTypography.caption),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              PillButton(
                label: 'Unduh PDF',
                icon: Icons.picture_as_pdf_outlined,
                loading: busy,
                onPressed: () => pdf(s),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Semantics(
          header: true,
          child: Text(
            'Tautan untuk tenaga kesehatan',
            style: AppTypography.heading,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tunjukkan kode QR saat kontrol. Tautan hanya bisa dibaca dan berakhir otomatis.',
          style: AppTypography.secondary,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 8,
          children: [
            for (final (h, l) in [
              (24, '1 hari'),
              (72, '3 hari'),
              (168, '7 hari'),
            ])
              PillChip(
                label: l,
                selected: hours == h,
                onTap: busy ? null : () => setState(() => hours = h),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        PillButton(
          label: 'Buat tautan dan kode QR',
          icon: Icons.qr_code_2_rounded,
          kind: PillButtonKind.secondary,
          loading: busy,
          onPressed: createLink,
        ),
        if (created?.url case final url?) ...[
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Semantics(
              label: 'Kode QR tautan ringkasan',
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  data: url,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          SelectableText(url, style: AppTypography.caption),
          Row(
            children: [
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: url));
                  if (context.mounted) announce(context, 'Tautan disalin');
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Salin'),
              ),
              TextButton.icon(
                onPressed: () =>
                    SharePlus.instance.share(ShareParams(text: url)),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Bagikan'),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        links.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => const SizedBox.shrink(),
          data: (items) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final l in items.where((l) => l.active))
                Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: ListTile(
                    title: Text(
                      'Ringkasan ${l.periodDays} hari${l.label == null ? '' : ' · ${l.label}'}',
                    ),
                    subtitle: Text(
                      'Berlaku sampai ${fmt.format(l.expiresAt.toLocal())} · dibuka ${l.accessCount}×',
                    ),
                    trailing: TextButton(
                      onPressed: () => revoke(l.id),
                      child: const Text('Cabut'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
