import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/error_messages.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/detail_kit.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../application/community_controller.dart';
import '../data/community_repository.dart';

class CommunityPrivacyScreen extends ConsumerStatefulWidget {
  const CommunityPrivacyScreen({super.key});

  @override
  ConsumerState<CommunityPrivacyScreen> createState() =>
      _CommunityPrivacyScreenState();
}

class _CommunityPrivacyScreenState
    extends ConsumerState<CommunityPrivacyScreen> {
  bool busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => busy = true);
    try {
      await action();
      ref.invalidate(communityPrivacyProvider);
      ref.invalidate(communityOverviewProvider);
      ref.invalidate(homeHighlightProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(done)));
      }
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

  Future<void> _leave(String communityId, String name) async {
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text('Keluar dari $name?'),
            content: const Text(
              'Partisipasimu di tantangannya berhenti dan aliasmu hilang dari papan peringkat.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(d).pop(false),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: () => Navigator.of(d).pop(true),
                child: const Text('Keluar'),
              ),
            ],
          ),
        ) ==
        true;
    if (!ok) return;
    await _run(
      () => ref.read(communityRepositoryProvider).leave(communityId),
      'Kamu keluar dari $name.',
    );
    ref.invalidate(myCommunitiesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(communityPrivacyProvider);
    return PageScaffold(
      title: 'Privasi komunitas',
      children: [
        value.when(
          loading: () => const SkeletonList(rows: 3),
          error: (e, _) => ErrorState(
            error: e,
            onRetry: () => ref.invalidate(communityPrivacyProvider),
          ),
          data: (CommunityPrivacy p) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DetailSection(
                title: 'Yang bisa dilihat anggota lain',
                children: [
                  for (final s in p.shared) _Bullet(s),
                  for (final m in p.memberships)
                    _Bullet('Alias di ${m.name}: ${m.alias}'),
                ],
              ),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: AppSpacing.sm),
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                decoration: BoxDecoration(
                  color: AppColors.brandTint,
                  borderRadius: AppRadius.cardRadius,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TIDAK PERNAH DIBAGIKAN',
                      style: AppTypography.overline,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    for (final s in p.neverShared) _Bullet(s),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Material(
                color: AppColors.surface,
                borderRadius: AppRadius.cardRadius,
                clipBehavior: Clip.antiAlias,
                child: SwitchListTile(
                  value: p.highlightsEnabled,
                  onChanged: busy
                      ? null
                      : (v) => _run(
                          () => ref
                              .read(communityRepositoryProvider)
                              .setHighlights(v),
                          v
                              ? 'Sorotan komunitas tampil di Beranda.'
                              : 'Sorotan komunitas disembunyikan dari Beranda.',
                        ),
                  title: Text(
                    'Tampilkan sorotan komunitas di Beranda',
                    style: AppTypography.body,
                  ),
                  subtitle: Text(
                    'Satu kartu progres tantangan atau pencapaian; hanya untukmu.',
                    style: AppTypography.caption,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                p.visibleOn.isEmpty
                    ? 'Aliasmu tidak tampil di papan peringkat mana pun.'
                    : 'Aliasmu tampil di: ${p.visibleOn.map((v) => v.title).join(', ')}.',
                style: AppTypography.secondary,
              ),
              const SizedBox(height: AppSpacing.sm),
              PillButton(
                label: 'Sembunyikan dari semua papan peringkat',
                kind: PillButtonKind.secondary,
                onPressed: busy || p.visibleOn.isEmpty
                    ? null
                    : () => _run(
                        () => ref
                            .read(communityRepositoryProvider)
                            .hideFromLeaderboards(),
                        'Aliasmu disembunyikan dari semua papan peringkat.',
                      ),
              ),
              if (p.memberships.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                for (final m in p.memberships)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => _leave(m.communityId, m.name),
                    child: Text(
                      'Keluar dari ${m.name}',
                      style: TextStyle(color: AppColors.errorForeground),
                    ),
                  ),
              ],
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: () => context.push('/settings/consent'),
                child: const Text('Atur persetujuan data'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('•  ', style: AppTypography.body),
        Expanded(child: Text(text, style: AppTypography.body)),
      ],
    ),
  );
}
