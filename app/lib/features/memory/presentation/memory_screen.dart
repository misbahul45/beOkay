import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../application/memory_controller.dart';
import '../data/memory_repository.dart';

class MemoryScreen extends ConsumerStatefulWidget {
  const MemoryScreen({super.key});

  @override
  ConsumerState<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends ConsumerState<MemoryScreen> {
  bool busy = false;

  MemoryRepository get _repo => ref.read(memoryRepositoryProvider);

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    setState(() => busy = true);
    try {
      await action();
      ref.invalidate(memoryOverviewProvider);
      ref.invalidate(personalizationSummaryProvider);
      if (mounted && done != null) {
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

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.of(d).pop(true),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _edit(MemoryItem m) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _EditMemoryDialog(item: m),
    );
    if (value == null || value.isEmpty || value == m.content) return;
    await _run(() => _repo.update(m, value), done: 'Ingatan diperbarui.');
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(memoryOverviewProvider);
    return PageScaffold(
      title: 'Memori & personalisasi',
      onRefresh: () async {
        ref.invalidate(memoryOverviewProvider);
        ref.invalidate(personalizationSummaryProvider);
        await ref.read(memoryOverviewProvider.future).catchError((_) => _empty);
      },
      children: [
        overview.when(
          loading: () => const SkeletonList(rows: 3),
          error: (e, _) => ErrorState(
            error: e,
            onRetry: () => ref.invalidate(memoryOverviewProvider),
          ),
          data: (o) => _Body(
            overview: o,
            busy: busy,
            onToggle: (v) => _run(
              () => _repo.setEnabled(v),
              done: v ? 'Ingatan diaktifkan.' : 'Ingatan dijeda.',
            ),
            onEdit: _edit,
            onPause: (m) =>
                _run(() => _repo.pause(m.id), done: 'Ingatan dijeda.'),
            onResume: (m) =>
                _run(() => _repo.resume(m.id), done: 'Ingatan dipakai lagi.'),
            onAccept: (m) =>
                _run(() => _repo.confirm(m.id), done: 'Ingatan disimpan.'),
            onReject: (m) =>
                _run(() => _repo.dismiss(m.id), done: 'Usulan ditolak.'),
            onHistory: (m) => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (_) => _HistorySheet(item: m),
            ),
            onDelete: (m) async {
              if (await _confirm(
                'Hapus ingatan ini?',
                '"${m.content}" tidak akan dipakai lagi untuk saran.',
                'Hapus',
              )) {
                await _run(() => _repo.remove(m.id), done: 'Ingatan dihapus.');
              }
            },
            onDeleteAll: () async {
              if (await _confirm(
                'Hapus semua ingatan?',
                'Semua yang diingat asisten dihapus. Catatan kesehatanmu tidak terpengaruh.',
                'Hapus semua',
              )) {
                await _run(_repo.removeAll, done: 'Semua ingatan dihapus.');
              }
            },
            onResetPersonalization: () async {
              if (await _confirm(
                'Atur ulang saran yang ditolak?',
                'Kata yang dipelajari dari saran yang kamu tolak akan dilupakan.',
                'Atur ulang',
              )) {
                await _run(
                  _repo.resetPersonalization,
                  done: 'Pembelajaran saran diatur ulang.',
                );
              }
            },
          ),
        ),
      ],
    );
  }

  static final _empty = MemoryOverview.fromJson(const {});
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.overview,
    required this.busy,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onDeleteAll,
    required this.onResetPersonalization,
    required this.onPause,
    required this.onResume,
    required this.onAccept,
    required this.onReject,
    required this.onHistory,
  });

  final MemoryOverview overview;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final ValueChanged<MemoryItem> onEdit,
      onDelete,
      onPause,
      onResume,
      onAccept,
      onReject,
      onHistory;
  final VoidCallback onDeleteAll, onResetPersonalization;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = overview;
    final personalization = ref.watch(personalizationSummaryProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Section(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: o.enabled,
            onChanged: busy ? null : onToggle,
            title: Text('Gunakan ingatan', style: AppTypography.bodyStrong),
            subtitle: Text(
              'Asisten hanya mengingat hal yang kamu setujui, untuk menyesuaikan saran.',
              style: AppTypography.secondary,
            ),
          ),
        ),
        if (!o.consentGiven) ...[
          const SizedBox(height: AppSpacing.sm),
          InfoCard(
            tone: InfoTone.warning,
            title: 'Ingatan tidak dipakai',
            text:
                'Persetujuan "Saran personal dari asisten beOkay" belum aktif, jadi ingatan tidak dipakai dan tidak bertambah.',
            action: PillButton(
              label: 'Buka persetujuan',
              kind: PillButtonKind.secondary,
              expand: false,
              onPressed: () => context.push(Routes.consentManagement),
            ),
          ),
        ] else if (!o.enabled) ...[
          const SizedBox(height: AppSpacing.sm),
          const InfoCard(
            tone: InfoTone.neutral,
            text:
                'Ingatan dijeda: tidak ada yang ditambah atau dipakai. Yang tersimpan tetap bisa kamu lihat dan hapus.',
          ),
        ],
        for (final c in o.conflicts) ...[
          const SizedBox(height: AppSpacing.sm),
          _ConflictCard(
            proposal: c,
            current: o.activeFor(c),
            busy: busy,
            onAccept: () => onAccept(c),
            onReject: () => onReject(c),
          ),
        ],
        if (o.proposals.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            header: true,
            child: Text('Usulan dari catatanmu', style: AppTypography.heading),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final p in o.proposals)
            _Section(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.content, style: AppTypography.bodyStrong),
                    Text(
                      'Dihitung dari sesi aktivitas yang kamu catat. Baru dipakai setelah kamu menyimpannya.',
                      style: AppTypography.caption,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      children: [
                        PillButton(
                          label: 'Simpan',
                          expand: false,
                          onPressed: busy ? null : () => onAccept(p),
                        ),
                        PillButton(
                          label: 'Tolak',
                          kind: PillButtonKind.secondary,
                          expand: false,
                          onPressed: busy ? null : () => onReject(p),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text('Yang kuingat', style: AppTypography.heading),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (o.items.isEmpty)
          Text(
            'Belum ada. Saat kamu menyebut kebiasaan, misalnya "aku lebih suka olahraga pagi", asisten akan bertanya dulu sebelum mengingatnya.',
            style: AppTypography.secondary,
          )
        else
          _Section(
            padding: 0,
            child: Column(
              children: [
                for (var i = 0; i < o.items.length; i++) ...[
                  _MemoryTile(
                    item: o.items[i],
                    busy: busy,
                    onEdit: () => onEdit(o.items[i]),
                    onDelete: () => onDelete(o.items[i]),
                    onPause: () => onPause(o.items[i]),
                    onHistory: () => onHistory(o.items[i]),
                  ),
                  if (i < o.items.length - 1)
                    Divider(height: 1, color: AppColors.border, indent: 16),
                ],
              ],
            ),
          ),
        if (o.paused.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            header: true,
            child: Text('Dijeda, tidak dipakai', style: AppTypography.heading),
          ),
          const SizedBox(height: AppSpacing.xs),
          _Section(
            padding: 0,
            child: Column(
              children: [
                for (final m in o.paused)
                  ListTile(
                    title: Text(
                      m.content,
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    subtitle: Text(
                      m.pauseReason == 'CONSENT_WITHDRAWN'
                          ? 'Dijeda karena persetujuan saran personal dicabut'
                          : 'Dijeda olehmu',
                      style: AppTypography.caption,
                    ),
                    trailing: TextButton(
                      onPressed: busy ? null : () => onResume(m),
                      child: const Text('Lanjutkan'),
                    ),
                    onTap: () => onHistory(m),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text(
            'Yang juga memengaruhi saran',
            style: AppTypography.heading,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _Section(
          padding: 0,
          child: Column(
            children: [
              ListTile(
                title: Text(
                  'Preferensi & alergi makanan',
                  style: AppTypography.bodyStrong,
                ),
                subtitle: Text(
                  'Dipakai untuk menyaring saran makanan.',
                  style: AppTypography.secondary,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.foodPreferences),
              ),
              Divider(height: 1, color: AppColors.border, indent: 16),
              ListTile(
                title: Text(
                  'Saran yang kamu tolak',
                  style: AppTypography.bodyStrong,
                ),
                subtitle: Text(
                  personalization == null
                      ? 'Tidak tersedia tanpa persetujuan saran personal.'
                      : personalization.dislikedTerms.isEmpty
                      ? 'Belum ada yang dipelajari.'
                      : 'Diturunkan: ${personalization.dislikedTerms.take(5).join(', ')}',
                  style: AppTypography.secondary,
                ),
                trailing: personalization == null || personalization.isEmpty
                    ? null
                    : TextButton(
                        onPressed: busy ? null : onResetPersonalization,
                        child: const Text('Atur ulang'),
                      ),
              ),
            ],
          ),
        ),
        if (o.items.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          TextButton(
            onPressed: busy ? null : onDeleteAll,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.errorForeground,
              backgroundColor: Colors.transparent,
              padding: EdgeInsets.zero,
            ),
            child: const Text('Hapus semua ingatan'),
          ),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.child, this.padding = 14});
  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(horizontal: padding, vertical: padding / 2),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg - 2),
      border: Border.all(color: AppColors.border),
    ),
    child: Material(color: Colors.transparent, child: child),
  );
}

class _MemoryTile extends StatelessWidget {
  const _MemoryTile({
    required this.item,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
    required this.onPause,
    required this.onHistory,
  });
  final MemoryItem item;
  final bool busy;
  final VoidCallback onEdit, onDelete, onPause, onHistory;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
    child: Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onHistory,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    item.typeLabel,
                    if (item.confirmedAt case final c?)
                      'dikonfirmasi ${DateFormat('d MMM', 'id_ID').format(c.toLocal())}',
                  ].join(' · '),
                  style: AppTypography.caption,
                ),
                Text(item.content, style: AppTypography.body),
                if (item.expiresAt case final e?)
                  Text(
                    '${item.temporary ? 'Berakhir otomatis' : 'Diperiksa ulang'} ${DateFormat('d MMM yyyy', 'id_ID').format(e.toLocal())}',
                    style: AppTypography.caption,
                  ),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: 'Jeda ingatan',
          onPressed: busy ? null : onPause,
          icon: const Icon(Icons.pause_circle_outline_rounded),
        ),
        IconButton(
          tooltip: 'Ubah ingatan',
          onPressed: busy ? null : onEdit,
          icon: Icon(Icons.edit_outlined, color: AppColors.brand),
        ),
        IconButton(
          tooltip: 'Hapus ingatan',
          onPressed: busy ? null : onDelete,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    ),
  );
}

class _EditMemoryDialog extends StatefulWidget {
  const _EditMemoryDialog({required this.item});
  final MemoryItem item;

  @override
  State<_EditMemoryDialog> createState() => _EditMemoryDialogState();
}

class _EditMemoryDialogState extends State<_EditMemoryDialog> {
  late final controller = TextEditingController(text: widget.item.content);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.item.kindLabel),
    content: TextField(
      controller: controller,
      autofocus: true,
      maxLength: 160,
      decoration: const InputDecoration(labelText: 'Isi ingatan'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Batal'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(controller.text.trim()),
        child: const Text('Simpan'),
      ),
    ],
  );
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({
    required this.proposal,
    required this.current,
    required this.busy,
    required this.onAccept,
    required this.onReject,
  });

  final MemoryItem proposal;
  final MemoryItem? current;
  final bool busy;
  final VoidCallback onAccept, onReject;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.warningBackground,
      borderRadius: BorderRadius.circular(AppRadius.lg - 2),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DUA INGATAN BERTENTANGAN',
          style: AppTypography.overline.copyWith(
            color: AppColors.warningForeground,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          current == null
              ? 'Baru: "${proposal.content}". Simpan untuk mengganti yang lama?'
              : 'Tersimpan: "${current!.content}". Baru: "${proposal.content}". Mana yang benar sekarang?',
          style: AppTypography.body,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            PillButton(
              label: 'Pakai yang baru',
              expand: false,
              onPressed: busy ? null : onAccept,
            ),
            PillButton(
              label: 'Tetap yang lama',
              kind: PillButtonKind.secondary,
              expand: false,
              onPressed: busy ? null : onReject,
            ),
          ],
        ),
      ],
    ),
  );
}

class _HistorySheet extends ConsumerWidget {
  const _HistorySheet({required this.item});

  final MemoryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder(
    future: ref.read(memoryRepositoryProvider).history(item.id),
    builder: (context, snap) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text('Riwayat', style: AppTypography.heading),
            ),
            Text(item.content, style: AppTypography.secondary),
            const SizedBox(height: AppSpacing.sm),
            if (snap.hasError)
              Text('Riwayat belum bisa dimuat.', style: AppTypography.body)
            else if (!snap.hasData)
              const LinearProgressIndicator()
            else
              for (final e in snap.data!.reversed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    [
                      DateFormat('d MMM', 'id_ID').format(e.at.toLocal()),
                      e.label,
                      if (e.change == 'SUPERSEDED') '(dulu: ${e.content})',
                      if (e.reason case final r? when e.change == 'PROPOSED') r,
                    ].join(' · '),
                    style: AppTypography.body,
                  ),
                ),
          ],
        ),
      ),
    ),
  );
}
