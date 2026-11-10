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

/// Tantangan hari aktif untuk satu komunitas. Skor hanya bertambah; tanpa poin untuk intensitas atau nilai kesehatan.
class ChallengeListScreen extends ConsumerWidget {
  const ChallengeListScreen({
    super.key,
    required this.communityId,
    required this.communityName,
  });
  final String communityId, communityName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(challengesProvider(communityId));
    return PageScaffold(
      title: communityName,
      onBack: () =>
          context.canPop() ? context.pop() : context.go(Routes.community),
      onRefresh: () async => ref.invalidate(challengesProvider(communityId)),
      children: [
        AsyncBody<List<Challenge>>(
          value: list,
          onRetry: () => ref.invalidate(challengesProvider(communityId)),
          data: (items) => items.isEmpty
              ? Text('Belum ada tantangan.', style: AppTypography.secondary)
              : Column(
                  children: [
                    for (final c in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: AppColors.surface,
                          borderRadius: AppRadius.cardRadius,
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            onTap: () =>
                                context.push('/challenge/${c.id}', extra: c),
                            title: Text(
                              c.title,
                              style: AppTypography.bodyStrong,
                            ),
                            subtitle: Text(
                              '${c.startsOn} – ${c.endsOn} · target ${c.targetDays} hari aktif${c.participating ? ' · kamu ikut' : ''}',
                              style: AppTypography.caption,
                            ),
                            trailing: const Icon(Icons.chevron_right),
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

class ChallengeDetailScreen extends ConsumerStatefulWidget {
  const ChallengeDetailScreen({super.key, required this.challenge});
  final Challenge challenge;
  @override
  ConsumerState<ChallengeDetailScreen> createState() => _ChallengeDetailState();
}

class _ChallengeDetailState extends ConsumerState<ChallengeDetailScreen> {
  late bool participating = widget.challenge.participating;
  bool visible = false;
  bool busy = false;
  ChallengeProgress? progress;
  Leaderboard? board;
  Object? error;

  @override
  void initState() {
    super.initState();
    if (participating) refresh();
  }

  CommunityRepository get repo => ref.read(communityRepositoryProvider);

  Future<void> refresh() async {
    try {
      final p = await repo.progress(widget.challenge.id);
      final b = await repo.leaderboard(widget.challenge.id);
      if (mounted) {
        setState(() {
          progress = p;
          board = b;
          visible = p.leaderboardVisible;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  Future<void> act(Future<void> Function() fn) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await fn();
      await refresh();
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.challenge;
    return PageScaffold(
      title: c.title,
      onBack: () => context.pop(),
      onRefresh: refresh,
      children: [
        Text(c.description, style: AppTypography.secondary),
        const SizedBox(height: AppSpacing.md),
        if (error != null) ...[
          if (error is ApiException &&
              (error! as ApiException).code == 'CONSENT_REQUIRED')
            InfoCard(
              tone: InfoTone.warning,
              title: 'Persetujuan diperlukan',
              text:
                  'Persetujuan yang dibutuhkan belum aktif: "Ikut tantangan kebiasaan" untuk ikut, "Tampil di papan peringkat" untuk menampilkan aliasmu. Atur di Persetujuan data.',
              action: PillButton(
                label: 'Buka persetujuan',
                kind: PillButtonKind.secondary,
                expand: false,
                onPressed: () => context.push(Routes.consentManagement),
              ),
            )
          else
            ErrorBanner(messageFor(error!)),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (!participating) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tampilkan aliasku di papan peringkat'),
            subtitle: const Text(
              'Opsional. Bisa dimatikan kapan saja dan berlaku segera.',
            ),
            value: visible,
            onChanged: busy ? null : (v) => setState(() => visible = v),
          ),
          PillButton(
            label: 'Ikut tantangan',
            loading: busy,
            onPressed: () => act(() async {
              await repo.joinChallenge(c.id, visible: visible);
              participating = true;
            }),
          ),
        ] else ...[
          if (progress != null) ...[
            Material(
              color: AppColors.surface,
              borderRadius: AppRadius.cardRadius,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Skormu: ${progress!.score.toStringAsFixed(1)}',
                      style: AppTypography.title,
                    ),
                    Text(
                      'Hari aktif: ${progress!.activityDays} dari target ${progress!.targetDays} · Check-in: ${progress!.checkinDays}',
                      style: AppTypography.secondary,
                    ),
                    const SizedBox(height: 4),
                    Text(progress!.note, style: AppTypography.caption),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          PillButton(
            label: 'Check-in hari ini',
            icon: Icons.check_circle_outline,
            kind: PillButtonKind.secondary,
            loading: busy,
            onPressed: () => act(() => repo.checkin(c.id)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tampilkan aliasku di papan peringkat'),
            value: visible,
            onChanged: busy
                ? null
                : (v) => act(() async {
                    await repo.setVisibility(c.id, v);
                  }),
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            header: true,
            child: Text('Papan peringkat', style: AppTypography.title),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (board == null)
            const LinearProgressIndicator()
          else if (board!.suppressed)
            InfoCard(
              tone: InfoTone.neutral,
              text:
                  board!.reason ??
                  'Papan peringkat tampil setelah cukup peserta bersedia tampil.',
            )
          else
            Column(
              children: [
                for (final r in board!.items)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: r.isMe
                          ? AppColors.primary
                          : AppColors.surfaceMuted,
                      child: Text(
                        '${r.rank}',
                        style: TextStyle(
                          fontSize: 12,
                          color: r.isMe
                              ? AppColors.onPrimary
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    title: Text(
                      r.isMe ? '${r.alias} (kamu)' : r.alias,
                      style: AppTypography.bodyStrong,
                    ),
                    trailing: Text(
                      r.score.toStringAsFixed(1),
                      style: AppTypography.secondaryStrong,
                    ),
                  ),
              ],
            ),
          const SizedBox(height: AppSpacing.md),
          PillButton(
            label: 'Keluar dari tantangan',
            kind: PillButtonKind.ghost,
            onPressed: busy
                ? null
                : () => act(() async {
                    await repo.leaveChallenge(c.id);
                    participating = false;
                    progress = null;
                    board = null;
                  }),
          ),
        ],
      ],
    );
  }
}
