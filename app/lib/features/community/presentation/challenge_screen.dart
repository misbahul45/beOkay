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
import '../../../core/widgets/detail_kit.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../notifications/application/realtime_controller.dart';
import '../application/community_controller.dart';
import '../data/community_repository.dart';
import 'community_widgets.dart';

String _errorText(Object e) => e is ApiException
    ? switch (e.code) {
        'CONSENT_REQUIRED' =>
          'Aktifkan persetujuan ikut tantangan di Persetujuan data.',
        'CHALLENGE_CLOSED' => 'Tantangan ini sudah ditutup.',
        'NOT_A_MEMBER' => 'Bergabunglah dengan komunitasnya dulu.',
        _ => messageFor(e),
      }
    : messageFor(e);

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class CommunityDetailScreen extends ConsumerStatefulWidget {
  const CommunityDetailScreen({
    super.key,
    required this.communityId,
    required this.communityName,
  });

  final String communityId, communityName;

  @override
  ConsumerState<CommunityDetailScreen> createState() =>
      _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends ConsumerState<CommunityDetailScreen> {
  bool busy = false;

  Future<void> _leave() async {
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('Keluar dari komunitas?'),
            content: const Text(
              'Partisipasimu di tantangan komunitas ini berhenti dan aliasmu hilang dari papan peringkat.',
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
    if (!ok || !mounted) return;
    setState(() => busy = true);
    try {
      await ref.read(communityRepositoryProvider).leave(widget.communityId);
      ref.invalidate(communityOverviewProvider);
      ref.invalidate(myCommunitiesProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) _snack(context, _errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(challengesProvider(widget.communityId));
    return PageScaffold(
      title: widget.communityName,
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Lainnya',
          onSelected: (v) =>
              v == 'leave' ? _leave() : context.push(Routes.communityPrivacy),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'privacy', child: Text('Privasi komunitas')),
            PopupMenuItem(value: 'leave', child: Text('Keluar dari komunitas')),
          ],
        ),
      ],
      onRefresh: () async {
        ref.invalidate(challengesProvider(widget.communityId));
        await ref
            .read(challengesProvider(widget.communityId).future)
            .then<void>((_) {}, onError: (_) {});
      },
      children: [
        value.when(
          loading: () => const SkeletonList(rows: 3),
          error: (e, _) =>
              InfoCard(tone: InfoTone.warning, text: _errorText(e)),
          data: (items) {
            final groups = [
              ('Sedang berjalan', items.where((c) => c.open).toList()),
              ('Segera dimulai', items.where((c) => c.scheduled).toList()),
              ('Riwayat', items.where((c) => c.closed).toList()),
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (title, list) in groups)
                  if (list.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 4,
                        bottom: AppSpacing.xs,
                        top: AppSpacing.sm,
                      ),
                      child: Semantics(
                        header: true,
                        child: Text(
                          title.toUpperCase(),
                          style: AppTypography.overline,
                        ),
                      ),
                    ),
                    for (final c in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: ChallengeCard(
                          challenge: c,
                          onTap: () => context.push('/challenge/${c.id}'),
                        ),
                      ),
                  ],
                if (items.isEmpty)
                  Text(
                    'Belum ada tantangan di komunitas ini.',
                    style: AppTypography.secondary,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class ChallengeDetailScreen extends ConsumerStatefulWidget {
  const ChallengeDetailScreen({super.key, required this.challengeId});

  final String challengeId;

  @override
  ConsumerState<ChallengeDetailScreen> createState() =>
      _ChallengeDetailScreenState();
}

class _ChallengeDetailScreenState extends ConsumerState<ChallengeDetailScreen> {
  bool busy = false;
  RealtimeController? _rt;
  String get _topic => 'challenge:${widget.challengeId}';

  @override
  void initState() {
    super.initState();
    try {
      final rt = ref.read(realtimeProvider.notifier);
      rt.subscribe(_topic);
      _rt = rt;
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      _rt?.unsubscribe(_topic);
    } catch (_) {}
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(challengeDetailProvider(widget.challengeId));
    ref.invalidate(leaderboardProvider(widget.challengeId));
    ref.invalidate(communityOverviewProvider);
    ref.invalidate(homeHighlightProvider);
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => busy = true);
    try {
      await action();
      _refresh();
      if (mounted) _snack(context, done);
    } catch (e) {
      if (mounted) _snack(context, _errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _join(ChallengeDetail c) async {
    var visible = false;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (s) => StatefulBuilder(
        builder: (s, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ikut "${c.title}"?', style: AppTypography.title),
                const SizedBox(height: 4),
                Text(
                  '${dateRange(c.startsOn, c.endsOn)} · target ${c.targetDays} hari aktif. Kamu bisa keluar kapan saja.',
                  style: AppTypography.secondary,
                ),
                const SizedBox(height: AppSpacing.sm),
                Material(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: SwitchListTile(
                    value: visible,
                    onChanged: (v) => set(() => visible = v),
                    title: Text(
                      'Tampilkan aliasku di papan peringkat',
                      style: AppTypography.body,
                    ),
                    subtitle: Text(
                      'Hanya alias (${c.alias}) dan skor. Bisa dimatikan kapan saja.',
                      style: AppTypography.caption,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                PillButton(
                  label: 'Ikut tantangan',
                  onPressed: () => Navigator.of(s).pop(true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await _run(
      () => ref
          .read(communityRepositoryProvider)
          .joinChallenge(c.id, visible: visible),
      'Kamu ikut tantangan ini.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(challengeDetailProvider(widget.challengeId));
    return PageScaffold(
      title: 'Tantangan',
      onRefresh: () async {
        _refresh();
        await ref
            .read(challengeDetailProvider(widget.challengeId).future)
            .then<void>((_) {}, onError: (_) {});
      },
      children: [
        value.when(
          loading: () => const SkeletonList(rows: 4),
          error: (e, _) =>
              InfoCard(tone: InfoTone.warning, text: _errorText(e)),
          data: (c) => _Body(
            c: c,
            busy: busy,
            onJoin: () => _join(c),
            onCheckin: () => _run(
              () => ref.read(communityRepositoryProvider).checkin(c.id),
              'Check-in hari ini tersimpan.',
            ),
            onLeave: () => _run(
              () => ref.read(communityRepositoryProvider).leaveChallenge(c.id),
              'Kamu keluar dari tantangan ini.',
            ),
            onVisible: (v) => _run(
              () =>
                  ref.read(communityRepositoryProvider).setVisibility(c.id, v),
              v
                  ? 'Aliasmu tampil di papan peringkat.'
                  : 'Aliasmu disembunyikan.',
            ),
          ),
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.c,
    required this.busy,
    required this.onJoin,
    required this.onCheckin,
    required this.onLeave,
    required this.onVisible,
  });

  final ChallengeDetail c;
  final bool busy;
  final VoidCallback onJoin, onCheckin, onLeave;
  final ValueChanged<bool> onVisible;

  @override
  Widget build(BuildContext context) {
    final colors = statusColors(c);
    final r = c.myResult;
    final active = c.activeDays ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: colors.tint,
            borderRadius: BorderRadius.circular(AppRadius.hero),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusPill(
                label: c.statusLabel,
                tint: AppColors.surface,
                ink: colors.ink,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(c.title, style: AppTypography.heading),
              Text(
                '${dateRange(c.startsOn, c.endsOn)} · ${c.communityName2} · ${c.participantsLabel ?? ''}',
                style: AppTypography.secondary,
              ),
            ],
          ),
        ),
        if (r != null)
          DetailSection(
            title: 'Hasilmu',
            children: [
              Row(
                children: [
                  Icon(
                    r.completed
                        ? Icons.check_circle_rounded
                        : Icons.flag_outlined,
                    color: r.completed ? AppColors.brand : AppColors.goalInk,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(r.label, style: AppTypography.title),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${r.finalActiveDays ?? 0} hari aktif dari target ${c.targetDays}${r.finalScore == null ? '' : ' · skor ${r.finalScore!.round()}'}',
                style: AppTypography.secondary,
              ),
              const SizedBox(height: 4),
              Text(
                r.completed
                    ? 'Usaha yang konsisten.'
                    : 'Ikut serta tetap dihitung sebagai usaha. Tantangan berikutnya sudah dibuka.',
                style: AppTypography.caption,
              ),
            ],
          ),
        if (c.team) _TeamSection(challengeId: c.id),
        if (c.participating && !c.closed)
          DetailSection(
            title: c.team ? 'Kontribusimu' : 'Progresmu',
            children: [
              Text(
                '$active dari ${c.targetDays} hari aktif',
                style: AppTypography.title,
              ),
              const SizedBox(height: 6),
              ProgressBar(ratio: c.targetDays == 0 ? 0 : active / c.targetDays),
              const SizedBox(height: 6),
              Text(
                'Skor ${(c.score ?? 0).round()} · ${c.activityDays ?? 0} hari dari aktivitas, ${c.checkinDays ?? 0} check-in. Hari istirahat tidak mengurangi skor.',
                style: AppTypography.caption,
              ),
              if (c.canCheckin) ...[
                const SizedBox(height: AppSpacing.sm),
                c.checkedInToday
                    ? PillButton(
                        label: 'Sudah check-in hari ini',
                        icon: Icons.check_circle_rounded,
                        kind: PillButtonKind.secondary,
                        expand: false,
                        onPressed: null,
                      )
                    : PillButton(
                        label: 'Check-in hari ini',
                        icon: Icons.check_rounded,
                        expand: false,
                        onPressed: busy ? null : onCheckin,
                      ),
              ],
            ],
          ),
        DetailSection(
          title: 'Cara kerja',
          children: [
            for (final rule in c.rules)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: AppTypography.body),
                    Expanded(child: Text(rule, style: AppTypography.secondary)),
                  ],
                ),
              ),
          ],
        ),
        if (c.participating || c.closed)
          _LeaderboardSection(c: c, busy: busy, onVisible: onVisible),
        if (c.canJoin) ...[
          const SizedBox(height: AppSpacing.md),
          PillButton(label: 'Ikut tantangan', onPressed: busy ? null : onJoin),
        ],
        if (c.participating && !c.closed) ...[
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: TextButton(
              onPressed: busy ? null : onLeave,
              child: const Text('Keluar dari tantangan'),
            ),
          ),
        ],
      ],
    );
  }
}

class _LeaderboardSection extends ConsumerWidget {
  const _LeaderboardSection({
    required this.c,
    required this.busy,
    required this.onVisible,
  });

  final ChallengeDetail c;
  final bool busy;
  final ValueChanged<bool> onVisible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(leaderboardProvider(c.id));
    return DetailSection(
      title: 'Papan peringkat',
      children: [
        board.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(_errorText(e), style: AppTypography.secondary),
          data: (b) => b.suppressed
              ? Text(
                  b.reason ?? 'Papan peringkat belum tampil.',
                  style: AppTypography.secondary,
                )
              : Column(
                  children: [
                    for (final row in b.items)
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: row.isMe
                              ? AppColors.brandTint
                              : AppColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 28,
                              child: Text(
                                '${row.rank}',
                                style: AppTypography.bodyStrong,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                row.isMe ? '${row.alias} (kamu)' : row.alias,
                                style: AppTypography.body,
                              ),
                            ),
                            Text(
                              row.score.round().toString(),
                              style: AppTypography.bodyStrong,
                            ),
                            if (!row.isMe)
                              TextButton(
                                onPressed: () => showReportSheet(
                                  context,
                                  ref,
                                  challengeId: c.id,
                                  alias: row.alias,
                                ),
                                child: const Text('Laporkan'),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        if (c.participating && !c.closed)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: c.leaderboardVisible,
            onChanged: busy ? null : onVisible,
            title: Text('Tampilkan aliasku', style: AppTypography.body),
            subtitle: Text(
              'Hanya alias dan skor. Berlaku segera.',
              style: AppTypography.caption,
            ),
          ),
      ],
    );
  }
}

const reportReasons = [
  ('ABUSIVE', 'Kasar atau menghina'),
  ('IMPERSONATION', 'Menyamar orang lain'),
  ('SPAM', 'Iklan atau spam'),
  ('OTHER', 'Lainnya'),
];

Future<void> showReportSheet(
  BuildContext context,
  WidgetRef ref, {
  required String challengeId,
  required String alias,
}) async {
  final reason = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Laporkan alias $alias?', style: AppTypography.title),
            const SizedBox(height: 4),
            Text(
              'Laporan ditinjau pemilik layanan. Alias disembunyikan sementara setelah 3 laporan dari orang berbeda.',
              style: AppTypography.secondary,
            ),
            const SizedBox(height: 8),
            for (final (code, label) in reportReasons)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(label),
                onTap: () => Navigator.pop(c, code),
              ),
          ],
        ),
      ),
    ),
  );
  if (reason == null || !context.mounted) return;
  try {
    final msg = await ref
        .read(communityRepositoryProvider)
        .reportAlias(challengeId, alias, reason);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(messageFor(e))));
    }
  }
}

class _TeamSection extends ConsumerWidget {
  const _TeamSection({required this.challengeId});

  final String challengeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(teamProgressProvider(challengeId)).value;
    if (t == null) return const SizedBox.shrink();
    if (!t.visible) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: InfoCard(
          tone: InfoTone.neutral,
          title: 'Progres tim',
          text:
              'Progres tim tampil setelah ada minimal ${t.minParticipants} anggota. Sekarang: ${t.participants} anggota.',
        ),
      );
    }
    final target = t.teamTargetDays ?? 0;
    final done = t.teamActiveDays ?? 0;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Semantics(
        container: true,
        label:
            'Progres tim: $done dari $target hari aktif, ${t.contributors ?? 0} anggota berkontribusi.',
        excludeSemantics: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          decoration: BoxDecoration(
            color: AppColors.brandTint,
            borderRadius: AppRadius.cardRadius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PROGRES TIM', style: AppTypography.overline),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  for (final (v, l) in [
                    ('$done', 'hari aktif tim'),
                    ('$target', 'target tim'),
                    ('${t.contributors ?? 0}', 'anggota berkontribusi'),
                  ])
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(v, style: AppTypography.metric),
                          Text(l, style: AppTypography.caption),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ProgressBar(ratio: target == 0 ? 0 : (done / target).clamp(0, 1)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Kontribusi per orang tidak ditampilkan. Tanpa nama dan tanpa nilai kesehatan.',
                style: AppTypography.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
