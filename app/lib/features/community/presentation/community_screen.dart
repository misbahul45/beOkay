import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../application/community_controller.dart';
import '../data/community_repository.dart';
import 'community_widgets.dart';

class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  String? region;
  bool busy = false;

  void _refresh() {
    ref.invalidate(communityOverviewProvider);
    ref.invalidate(myCommunitiesProvider);
    if (region != null) ref.invalidate(communitiesInRegionProvider(region!));
  }

  Future<void> _join(Community c) async {
    final alias = await showAliasSheet(context, communityName: c.name);
    if (alias == null || !mounted) return;
    setState(() => busy = true);
    try {
      await ref.read(communityRepositoryProvider).join(c.id, alias);
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kamu bergabung sebagai $alias.')),
        );
      }
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

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(communityOverviewProvider);
    return PageScaffold(
      title: 'Komunitas',
      onBack: () =>
          context.canPop() ? context.pop() : context.go(Routes.profile),
      actions: [
        IconButton(
          tooltip: 'Privasi komunitas',
          onPressed: () => context.push(Routes.communityPrivacy),
          icon: const Icon(Icons.shield_outlined),
        ),
      ],
      onRefresh: () async {
        _refresh();
        await ref
            .read(communityOverviewProvider.future)
            .then<void>((_) {}, onError: (_) {});
      },
      children: [
        Text(
          'Opsional. Kamu tampil dengan alias, bukan namamu.',
          style: AppTypography.secondary,
        ),
        const SizedBox(height: AppSpacing.md),
        overview.when(
          loading: () => const SkeletonList(rows: 3),
          error: (e, _) => ErrorState(error: e, onRetry: _refresh),
          data: (o) => _Overview(
            overview: o,
            onOpen: (id) => context.push('/challenge/$id'),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const _Heading('Temukan di wilayahmu'),
        AsyncBody<List<Region>>(
          value: ref.watch(regionsProvider),
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
                loading: () => const SkeletonList(rows: 2),
                error: (e, _) =>
                    e is ApiException && e.code == 'CONSENT_REQUIRED'
                    ? const SizedBox.shrink()
                    : Text(messageFor(e), style: AppTypography.secondary),
                data: (items) => Column(
                  children: [
                    for (final c in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _CommunityCard(
                          community: c,
                          busy: busy,
                          onJoin: () => _join(c),
                          onOpen: () =>
                              context.push('/community/${c.id}', extra: c.name),
                        ),
                      ),
                  ],
                ),
              ),
        ],
        const SizedBox(height: AppSpacing.md),
        Material(
          color: AppColors.surfaceMuted,
          borderRadius: AppRadius.cardRadius,
          child: ListTile(
            leading: Icon(Icons.lock_outline, color: AppColors.brand),
            title: Text(
              'Yang dibagikan hanya alias, dan skor bila kamu izinkan.',
              style: AppTypography.secondaryStrong,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(Routes.communityPrivacy),
          ),
        ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.xs),
    child: Semantics(
      header: true,
      child: Text(text.toUpperCase(), style: AppTypography.overline),
    ),
  );
}

class _Overview extends StatelessWidget {
  const _Overview({required this.overview, required this.onOpen});

  final CommunityOverview overview;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final badges = [...o.recognitions, ...o.upcomingRecognitions];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (o.consentRequired)
          InfoCard(
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
          ),
        if (!o.consentRequired) ...[
          const _Heading('Tantanganmu'),
          if (o.challenges.isEmpty)
            Text(
              o.memberships.isEmpty
                  ? 'Gabung dengan komunitas di wilayahmu untuk ikut tantangan.'
                  : 'Belum ikut tantangan. Buka komunitasmu untuk memilih.',
              style: AppTypography.secondary,
            ),
          for (final c in o.challenges)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ChallengeCard(challenge: c, onTap: () => onOpen(c.id)),
            ),
        ],
        if (badges.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          const _Heading('Pencapaian pribadi'),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final b in badges) RecognitionBadge(recognition: b),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Hanya kamu yang melihat pencapaian ini.',
            style: AppTypography.caption,
          ),
        ],
        if (o.memberships.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          const _Heading('Komunitasku'),
          for (final m in o.memberships)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Material(
                color: AppColors.surface,
                borderRadius: AppRadius.cardRadius,
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  onTap: () => context.push(
                    '/community/${m.communityId}',
                    extra: m.name,
                  ),
                  title: Text(m.name, style: AppTypography.bodyStrong),
                  subtitle: Text(
                    'Alias: ${m.alias} · ${m.openChallenges} tantangan berjalan',
                    style: AppTypography.caption,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _CommunityCard extends StatelessWidget {
  const _CommunityCard({
    required this.community,
    required this.busy,
    required this.onJoin,
    required this.onOpen,
  });

  final Community community;
  final bool busy;
  final VoidCallback onJoin, onOpen;

  @override
  Widget build(BuildContext context) {
    final c = community;
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadius.cardRadius,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.name, style: AppTypography.bodyStrong),
            Text(c.description, style: AppTypography.caption),
            Text(
              'Anggota: ${c.memberCountLabel}',
              style: AppTypography.caption,
            ),
            if (c.challenges.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              for (final ch in c.challenges)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.flag_outlined,
                        size: 16,
                        color: AppColors.goalInk,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${ch.title} · ${ch.statusLabel.toLowerCase()} · ${ch.participantsLabel ?? ''}',
                          style: AppTypography.caption,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: AppSpacing.sm),
            c.joined
                ? PillButton(
                    label: 'Buka komunitas',
                    kind: PillButtonKind.secondary,
                    expand: false,
                    onPressed: onOpen,
                  )
                : PillButton(
                    label: 'Gabung',
                    expand: false,
                    onPressed: busy ? null : onJoin,
                  ),
          ],
        ),
      ),
    );
  }
}
