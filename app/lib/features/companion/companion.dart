import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/a11y/announce.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/error_messages.dart';
import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/choice_chips.dart';
import '../../core/widgets/info_card.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/pill_button.dart';

class CompanionLink {
  CompanionLink.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      label = j['label'] as String,
      active = j['active'] == true,
      viewCount = (j['viewCount'] as num?)?.toInt() ?? 0,
      expiresAt = DateTime.parse(j['expiresAt'] as String).toLocal(),
      lastViewedAt = j['lastViewedAt'] == null
          ? null
          : DateTime.parse(j['lastViewedAt'] as String).toLocal(),
      createdAt = DateTime.parse(j['createdAt'] as String).toLocal(),
      url = j['url'] as String?;
  final String id, label;
  final bool active;
  final int viewCount;
  final DateTime expiresAt, createdAt;
  final DateTime? lastViewedAt;
  final String? url;
}

class CompanionRepository {
  CompanionRepository(this.api);
  final ApiClient api;
  Future<List<CompanionLink>> list() async => [
    for (final l
        in (await api.get('/api/me/companions')).object['items'] as List)
      CompanionLink.fromJson(l as Map<String, dynamic>),
  ];
  Future<CompanionLink> create(String label, int days) async =>
      CompanionLink.fromJson(
        (await api.post(
          '/api/me/companions',
          body: {'label': label, 'days': days, 'confirm': true},
        )).object,
      );
  Future<void> revoke(String id) => api.post('/api/me/companions/$id/revoke');
}

final companionRepositoryProvider = Provider<CompanionRepository>(
  (ref) => CompanionRepository(ref.watch(apiClientProvider)),
);
final companionsProvider = FutureProvider.autoDispose<List<CompanionLink>>(
  (ref) => ref.watch(companionRepositoryProvider).list(),
);

class CompanionScreen extends ConsumerStatefulWidget {
  const CompanionScreen({super.key});
  @override
  ConsumerState<CompanionScreen> createState() => _CompanionScreenState();
}

class _CompanionScreenState extends ConsumerState<CompanionScreen> {
  final label = TextEditingController();
  int days = 90;
  bool busy = false;
  CompanionLink? created;
  String? error;
  bool needsConsent = false;

  @override
  void dispose() {
    label.dispose();
    super.dispose();
  }

  Future<void> create() async {
    final name = label.text.trim();
    if (name.isEmpty) {
      setState(
        () => error = 'Tulis nama atau hubungan pendamping, misalnya "Anak".',
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Buat tautan pendamping?'),
        content: Text(
          'Pemegang tautan bisa melihat ringkasan mingguanmu dan jam pengingat obat yang belum dikonfirmasi selama $days hari. Catatan mentah, nama makanan, nama obat, dan angka glukosa tidak ditampilkan.',
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
    setState(() {
      busy = true;
      error = null;
      needsConsent = false;
    });
    try {
      final link = await ref
          .read(companionRepositoryProvider)
          .create(name, days);
      ref.invalidate(companionsProvider);
      label.clear();
      setState(() => created = link);
      if (mounted) announce(context, 'Tautan pendamping dibuat');
    } on ApiException catch (e) {
      setState(() {
        needsConsent = e.code == 'CONSENT_REQUIRED';
        error = needsConsent
            ? 'Aktifkan "Berbagi ringkasan mingguan dengan pendamping" di Persetujuan data.'
            : messageFor(e);
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> revoke(CompanionLink l) async {
    try {
      await ref.read(companionRepositoryProvider).revoke(l.id);
      if (created?.id == l.id) setState(() => created = null);
      ref.invalidate(companionsProvider);
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
    final links = ref.watch(companionsProvider);
    final fmt = DateFormat('d MMM', 'id_ID');
    return PageScaffold(
      title: 'Pendamping',
      children: [
        const InfoCard(
          tone: InfoTone.neutral,
          text:
              'Pendamping bisa melihat ringkasan mingguan dan pengingat obat yang belum dikonfirmasi lewat tautan. Catatan mentah, nama makanan, dan angka per catatan tidak ditampilkan.',
        ),
        const SizedBox(height: AppSpacing.md),
        links.when(
          loading: () => const SkeletonList(rows: 2),
          error: (e, _) => ErrorState(
            error: e,
            onRetry: () => ref.invalidate(companionsProvider),
          ),
          data: (items) {
            final active = items.where((l) => l.active).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pendamping aktif', style: AppTypography.title),
                if (active.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Belum ada.', style: AppTypography.secondary),
                  ),
                for (final l in active)
                  Card(
                    margin: const EdgeInsets.only(top: AppSpacing.xs),
                    child: ListTile(
                      leading: const Icon(Icons.family_restroom_outlined),
                      title: Text(l.label),
                      subtitle: Text(
                        'Dibuat ${fmt.format(l.createdAt)} · ${l.lastViewedAt == null ? 'belum dilihat' : 'dilihat ${fmt.format(l.lastViewedAt!)}'} · berakhir ${fmt.format(l.expiresAt)}',
                      ),
                      trailing: TextButton(
                        onPressed: () => revoke(l),
                        child: const Text('Cabut'),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        Text('Label hanya terlihat olehmu.', style: AppTypography.caption),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: label,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: 'Nama atau hubungan',
            hintText: 'Contoh: Anak (Rina)',
          ),
        ),
        Text('Berlaku', style: AppTypography.bodyStrong),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (final d in [30, 90, 180])
              PillChip(
                label: '$d hari',
                selected: days == d,
                onTap: busy ? null : () => setState(() => days = d),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        PillButton(
          label: 'Buat tautan pendamping',
          icon: Icons.link_rounded,
          loading: busy,
          onPressed: create,
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.xs),
          InfoCard(
            tone: InfoTone.warning,
            text: error!,
            action: needsConsent
                ? PillButton(
                    label: 'Buka persetujuan',
                    kind: PillButtonKind.secondary,
                    expand: false,
                    onPressed: () => context.push(Routes.consentManagement),
                  )
                : null,
          ),
        ],
        if (created?.url case final url?) ...[
          const SizedBox(height: AppSpacing.sm),
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
                onPressed: () => SharePlus.instance.share(
                  ShareParams(
                    text:
                        'Ringkasan mingguan beOkay (baca-saja, bisa dicabut): $url',
                  ),
                ),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Bagikan'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
