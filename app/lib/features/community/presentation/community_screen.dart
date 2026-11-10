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
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../application/community_controller.dart';
import '../data/community_repository.dart';

bool _isConsent(Object e) => e is ApiException && e.code == 'CONSENT_REQUIRED';

/// Komunitas berbasis wilayah (provinsi). Bergabung sukarela dengan alias; yang terlihat anggota lain hanya aliasmu.
class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});
  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  String? region;
  bool busy = false;

  Future<void> join(Community c) async {
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => const _AliasDialog(),
    );
    if (text == null || !mounted) return;
    setState(() => busy = true);
    try {
      await ref.read(communityRepositoryProvider).join(c.id, text);
      ref.invalidate(myCommunitiesProvider);
      if (region != null) ref.invalidate(communitiesInRegionProvider(region!));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException && e.code == 'ALIAS_TAKEN'
                  ? 'Alias itu sudah dipakai. Pilih yang lain.'
                  : e is ApiException && e.code == 'INVALID_ALIAS'
                  ? e.message
                  : messageFor(e),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> leave(String communityId) async {
    setState(() => busy = true);
    try {
      await ref.read(communityRepositoryProvider).leave(communityId);
      ref.invalidate(myCommunitiesProvider);
      if (region != null) ref.invalidate(communitiesInRegionProvider(region!));
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

  @override
  Widget build(BuildContext context) {
    final regions = ref.watch(regionsProvider);
    final mine = ref.watch(myCommunitiesProvider);
    return PageScaffold(
      title: 'Komunitas',
      onBack: () =>
          context.canPop() ? context.pop() : context.go(Routes.profile),
      onRefresh: () async {
        ref.invalidate(myCommunitiesProvider);
        if (region != null) {
          ref.invalidate(communitiesInRegionProvider(region!));
        }
      },
      children: [
        Semantics(
          header: true,
          child: Text('Komunitasku', style: AppTypography.title),
        ),
        const SizedBox(height: AppSpacing.xs),
        mine.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => _isConsent(e)
              ? _consentCard(context)
              : Text(messageFor(e), style: AppTypography.secondary),
          data: (items) => items.isEmpty
              ? Text(
                  'Belum bergabung dengan komunitas mana pun.',
                  style: AppTypography.secondary,
                )
              : Column(
                  children: [
                    for (final m in items)
                      _MineTile(
                        m: m,
                        busy: busy,
                        onLeave: () => leave(m.communityId),
                        onOpen: () => context.push(
                          '/community/${m.communityId}',
                          extra: m.name,
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text('Cari di wilayahmu', style: AppTypography.title),
        ),
        const SizedBox(height: AppSpacing.xs),
        AsyncBody<List<Region>>(
          value: regions,
          onRetry: () => ref.invalidate(regionsProvider),
          skeletonRows: 1,
          data: (list) => DropdownButtonFormField<String>(
            initialValue: region,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Provinsi'),
            items: [
              for (final r in list)
                DropdownMenuItem(value: r.code, child: Text(r.name)),
            ],
            onChanged: (v) => setState(() => region = v),
          ),
        ),
        if (region != null) ...[
          const SizedBox(height: AppSpacing.sm),
          ref
              .watch(communitiesInRegionProvider(region!))
              .when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) =>
                    Text(messageFor(e), style: AppTypography.secondary),
                data: (items) => Column(
                  children: [
                    for (final c in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: AppColors.surface,
                          borderRadius: AppRadius.cardRadius,
                          child: Padding(
                            padding: const EdgeInsets.all(
                              AppSpacing.cardPadding,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.name, style: AppTypography.bodyStrong),
                                Text(
                                  c.description,
                                  style: AppTypography.caption,
                                ),
                                Text(
                                  'Anggota: ${c.memberCountLabel}',
                                  style: AppTypography.caption,
                                ),
                                const SizedBox(height: 8),
                                c.joined
                                    ? const StatusBadge(
                                        label: 'Kamu anggota',
                                        tone: InfoTone.info,
                                      )
                                    : PillButton(
                                        label: 'Gabung',
                                        expand: false,
                                        onPressed: busy ? null : () => join(c),
                                      ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
        ],
      ],
    );
  }

  Widget _consentCard(BuildContext context) => InfoCard(
    tone: InfoTone.warning,
    title: 'Persetujuan diperlukan',
    text:
        'Aktifkan "Bergabung dengan komunitas wilayah" di Persetujuan data untuk memakai komunitas.',
    action: PillButton(
      label: 'Buka persetujuan',
      kind: PillButtonKind.secondary,
      expand: false,
      onPressed: () => context.push(Routes.consentManagement),
    ),
  );
}

class _MineTile extends StatelessWidget {
  const _MineTile({
    required this.m,
    required this.busy,
    required this.onLeave,
    required this.onOpen,
  });
  final MyMembership m;
  final bool busy;
  final VoidCallback onLeave, onOpen;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: AppColors.surface,
      borderRadius: AppRadius.cardRadius,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onOpen,
        title: Text(m.name, style: AppTypography.bodyStrong),
        subtitle: Text(
          'Aliasmu: ${m.alias} · ${m.region}',
          style: AppTypography.caption,
        ),
        trailing: TextButton(
          onPressed: busy ? null : onLeave,
          child: const Text('Keluar'),
        ),
      ),
    ),
  );
}

/// Dialog alias dengan controller sendiri supaya dibuang setelah animasi tutup selesai.
class _AliasDialog extends StatefulWidget {
  const _AliasDialog();
  @override
  State<_AliasDialog> createState() => _AliasDialogState();
}

class _AliasDialogState extends State<_AliasDialog> {
  final alias = TextEditingController();

  @override
  void dispose() {
    alias.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Pilih alias'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Anggota lain hanya melihat alias ini, bukan namamu. Jangan pakai nama asli, surel, atau nomor telepon.',
        ),
        const SizedBox(height: 8),
        AppTextField(
          label: 'Alias',
          hint: 'mis. Jalan Pagi',
          controller: alias,
          maxLength: 20,
          autofocus: true,
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, alias.text.trim()),
        child: const Text('Gabung'),
      ),
    ],
  );
}
