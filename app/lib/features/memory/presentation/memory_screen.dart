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
import '../../../core/widgets/soft_card.dart';
import '../application/memory_controller.dart';
import '../data/memory_repository.dart';

String _day(DateTime d) => DateFormat('d MMM', 'id_ID').format(d.toLocal());

class MemoryScreen extends ConsumerStatefulWidget {
  const MemoryScreen({super.key});

  @override
  ConsumerState<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends ConsumerState<MemoryScreen> {
  bool busy = false;
  String? selectedId;

  MemoryRepository get _repo => ref.read(memoryRepositoryProvider);

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    setState(() => busy = true);
    try {
      await action();
      ref.invalidate(memoryOverviewProvider);
      ref.invalidate(personalizationSummaryProvider);
      ref.invalidate(memoryHistoryProvider);
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

  Future<void> _delete(MemoryItem m) async {
    if (await _confirm(
      'Hapus ingatan ini?',
      '"${m.content}" tidak akan dipakai lagi untuk saran.',
      'Hapus',
    )) {
      if (selectedId == m.id) setState(() => selectedId = null);
      await _run(() => _repo.remove(m.id), done: 'Ingatan dihapus.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(memoryOverviewProvider);
    return PageScaffold(
      title: 'Ingatan asisten',
      maxContentWidth: 720,
      onRefresh: () async {
        ref.invalidate(memoryOverviewProvider);
        ref.invalidate(personalizationSummaryProvider);
        ref.invalidate(memoryHistoryProvider);
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
            selectedId: selectedId,
            onSelect: (m) => setState(() => selectedId = m.id),
            onToggle: (v) => _run(
              () => _repo.setEnabled(v),
              done: v ? 'Ingatan diaktifkan.' : 'Ingatan dijeda.',
            ),
            onEdit: _edit,
            onDelete: _delete,
            onPause: (m) =>
                _run(() => _repo.pause(m.id), done: 'Ingatan dijeda.'),
            onResume: (m) =>
                _run(() => _repo.resume(m.id), done: 'Ingatan dipakai lagi.'),
            onAccept: (m) =>
                _run(() => _repo.confirm(m.id), done: 'Ingatan disimpan.'),
            onReject: (m) =>
                _run(() => _repo.dismiss(m.id), done: 'Usulan ditolak.'),
            onDeleteAll: () async {
              if (await _confirm(
                'Hapus semua ingatan?',
                'Semua yang diingat asisten dihapus. Catatan kesehatanmu tidak terpengaruh.',
                'Hapus semua',
              )) {
                setState(() => selectedId = null);
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
    required this.selectedId,
    required this.onSelect,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onDeleteAll,
    required this.onResetPersonalization,
    required this.onPause,
    required this.onResume,
    required this.onAccept,
    required this.onReject,
  });

  final MemoryOverview overview;
  final bool busy;
  final String? selectedId;
  final ValueChanged<bool> onToggle;
  final ValueChanged<MemoryItem> onSelect,
      onEdit,
      onDelete,
      onPause,
      onResume,
      onAccept,
      onReject;
  final VoidCallback onDeleteAll, onResetPersonalization;

  MemoryItem? get _selected {
    final all = [...overview.items, ...overview.paused];
    for (final m in all) {
      if (m.id == selectedId) return m;
    }
    return all.isEmpty ? null : all.first;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = overview;
    final personalization = ref.watch(personalizationSummaryProvider).value;
    final selected = _selected;
    const gap = SizedBox(height: AppSpacing.sm);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!o.consentGiven) ...[
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
          gap,
        ] else if (!o.enabled) ...[
          const InfoCard(
            tone: InfoTone.neutral,
            text:
                'Ingatan dijeda: tidak ada yang ditambah atau dipakai. Yang tersimpan tetap bisa kamu lihat dan hapus.',
          ),
          gap,
        ],
        for (final c in o.conflicts) ...[
          _ConflictCard(
            proposal: c,
            current: o.activeFor(c),
            busy: busy,
            onAccept: () => onAccept(c),
            onReject: () => onReject(c),
          ),
          gap,
        ],
        if (o.proposals.isNotEmpty) ...[
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Overline('USULAN DARI CATATANMU'),
                for (final p in o.proposals) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(p.content, style: AppTypography.bodyStrong),
                  Text(
                    'Dihitung dari sesi aktivitas yang kamu catat. Baru dipakai setelah kamu menyimpannya.',
                    style: AppTypography.caption,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      PillButton(
                        label: 'Simpan',
                        kind: PillButtonKind.ink,
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
              ],
            ),
          ),
          gap,
        ],
        SoftCard(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Overline(
                o.items.isEmpty
                    ? 'DIPAKAI UNTUK SARAN'
                    : 'DIPAKAI UNTUK SARAN · ${o.items.length}',
              ),
              const SizedBox(height: AppSpacing.xs),
              if (o.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(
                    right: AppSpacing.xs,
                    bottom: AppSpacing.xs,
                  ),
                  child: Text(
                    'Belum ada. Saat kamu menyebut kebiasaan, misalnya "aku lebih suka olahraga pagi", asisten akan bertanya dulu sebelum mengingatnya.',
                    style: AppTypography.secondary,
                  ),
                )
              else ...[
                for (final m in o.items)
                  _MemoryRow(
                    item: m,
                    selected: selected?.id == m.id,
                    busy: busy,
                    actionLabel: 'Jeda',
                    onAction: () => onPause(m),
                    onSelect: () => onSelect(m),
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    'Ketuk ingatan untuk melihat riwayat, mengubah, atau menghapusnya.',
                    style: AppTypography.caption,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (o.paused.isNotEmpty) ...[
          gap,
          SoftCard(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Overline('DIJEDA · TIDAK DIPAKAI'),
                const SizedBox(height: AppSpacing.xs),
                for (final m in o.paused)
                  _MemoryRow(
                    item: m,
                    selected: selected?.id == m.id,
                    busy: busy,
                    actionLabel: 'Lanjutkan',
                    onAction: () => onResume(m),
                    onSelect: () => onSelect(m),
                  ),
              ],
            ),
          ),
        ],
        if (selected != null) ...[
          gap,
          _DetailCard(
            item: selected,
            busy: busy,
            onEdit: () => onEdit(selected),
            onDelete: () => onDelete(selected),
          ),
        ],
        gap,
        SoftCard(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Overline('PENGATURAN'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: o.enabled,
                onChanged: busy ? null : onToggle,
                title: Text('Gunakan ingatan', style: AppTypography.bodyStrong),
                subtitle: Text(
                  'Asisten hanya mengingat hal yang kamu setujui, untuk menyesuaikan saran.',
                  style: AppTypography.secondary,
                ),
              ),
            ],
          ),
        ),
        gap,
        SoftCard(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Overline('YANG JUGA MEMENGARUHI SARAN'),
              ListTile(
                contentPadding: const EdgeInsets.only(right: AppSpacing.xs),
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
              ListTile(
                contentPadding: const EdgeInsets.only(right: AppSpacing.xs),
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
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: busy ? null : onDeleteAll,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.errorForeground,
                backgroundColor: Colors.transparent,
              ),
              child: const Text('Hapus semua ingatan'),
            ),
          ),
        ],
      ],
    );
  }
}

class _MemoryRow extends StatelessWidget {
  const _MemoryRow({
    required this.item,
    required this.selected,
    required this.busy,
    required this.actionLabel,
    required this.onAction,
    required this.onSelect,
  });

  final MemoryItem item;
  final bool selected, busy;
  final String actionLabel;
  final VoidCallback onAction, onSelect;

  @override
  Widget build(BuildContext context) {
    final paused = item.paused;
    final meta = paused
        ? (item.pauseReason == 'CONSENT_WITHDRAWN'
              ? 'Dijeda karena persetujuan saran personal dicabut'
              : 'Dijeda olehmu')
        : [
            item.typeLabel,
            if (item.confirmedAt case final c?) 'dikonfirmasi ${_day(c)}',
          ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              hint: 'Tampilkan riwayat',
              child: InkWell(
                onTap: onSelect,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: paused
                                ? AppColors.decorative
                                : AppColors.brand,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.content,
                              style: paused
                                  ? AppTypography.body.copyWith(
                                      color: AppColors.textSecondary,
                                    )
                                  : AppTypography.bodyStrong,
                            ),
                            Text(meta, style: AppTypography.caption),
                            if (item.expiresAt case final e?)
                              Text(
                                '${item.temporary ? 'Berakhir otomatis' : 'Diperiksa ulang'} ${DateFormat('d MMM yyyy', 'id_ID').format(e.toLocal())}',
                                style: AppTypography.caption,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          _CompactPill(
            label: actionLabel,
            semanticsLabel: '$actionLabel: ${item.content}',
            onPressed: busy ? null : onAction,
          ),
        ],
      ),
    );
  }
}

class _CompactPill extends StatelessWidget {
  const _CompactPill({
    required this.label,
    required this.semanticsLabel,
    required this.onPressed,
  });

  final String label, semanticsLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null,
    label: semanticsLabel,
    excludeSemantics: true,
    onTap: onPressed,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        backgroundColor: AppColors.surface,
        side: BorderSide(color: AppColors.border),
        shape: const StadiumBorder(),
        minimumSize: const Size(56, AppSpacing.chipHeight),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        tapTargetSize: MaterialTapTargetSize.padded,
        textStyle: AppTypography.secondaryStrong,
      ),
      child: Text(label),
    ),
  );
}

class _DetailCard extends ConsumerWidget {
  const _DetailCard({
    required this.item,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
  });

  final MemoryItem item;
  final bool busy;
  final VoidCallback onEdit, onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(memoryHistoryProvider(item.id));
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Overline('RIWAYAT · ${item.content.toUpperCase()}'),
          const SizedBox(height: AppSpacing.sm),
          history.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => Row(
              children: [
                Expanded(
                  child: Text(
                    'Riwayat belum bisa dimuat.',
                    style: AppTypography.secondary,
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      ref.invalidate(memoryHistoryProvider(item.id)),
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
            data: (entries) => entries.isEmpty
                ? Text('Belum ada perubahan.', style: AppTypography.secondary)
                : Column(
                    children: [
                      for (final (i, e) in entries.reversed.indexed)
                        _HistoryLine(entry: e, latest: i == 0),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              Tooltip(
                message: 'Ubah ingatan',
                child: TextButton.icon(
                  onPressed: busy ? null : onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Ubah'),
                ),
              ),
              Tooltip(
                message: 'Hapus ingatan',
                child: TextButton.icon(
                  onPressed: busy ? null : onDelete,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.errorForeground,
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Hapus'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryLine extends StatelessWidget {
  const _HistoryLine({required this.entry, required this.latest});

  final MemoryRevisionEntry entry;
  final bool latest;

  @override
  Widget build(BuildContext context) {
    final text = [
      _day(entry.at),
      entry.label,
      if (entry.change == 'SUPERSEDED') '(dulu: ${entry.content})',
      if (entry.reason case final r? when entry.change == 'PROPOSED') r,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: latest ? AppColors.brand : AppColors.decorative,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: AppTypography.body)),
        ],
      ),
    );
  }
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
  Widget build(BuildContext context) {
    Widget value(String label, String text, {required bool fresh}) => Semantics(
      container: true,
      label: '$label: $text',
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          color: fresh
              ? AppColors.surface
              : AppColors.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(AppRadius.md - 2),
          border: fresh ? Border.all(color: AppColors.brand) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: AppTypography.overline.copyWith(
                color: fresh ? AppColors.brand : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              text,
              style: fresh
                  ? AppTypography.bodyStrong
                  : AppTypography.body.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
    return SoftCard(
      color: AppColors.warningBackground,
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Overline(
            'DUA INGATAN BERTENTANGAN',
            color: AppColors.warningForeground,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text('Mana yang benar sekarang?', style: AppTypography.title),
          const SizedBox(height: AppSpacing.sm),
          if (current case final c?) ...[
            value('Tersimpan', c.content, fresh: false),
            const SizedBox(height: AppSpacing.xs),
          ],
          value('Baru', proposal.content, fresh: true),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, c) {
              final accept = PillButton(
                label: 'Pakai yang baru',
                kind: PillButtonKind.ink,
                onPressed: busy ? null : onAccept,
              );
              final keep = PillButton(
                label: current == null ? 'Tolak' : 'Tetap yang lama',
                kind: PillButtonKind.secondary,
                onPressed: busy ? null : onReject,
              );
              if (c.maxWidth < 360) {
                return Column(
                  children: [
                    accept,
                    const SizedBox(height: AppSpacing.xs),
                    keep,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: accept),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: keep),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
