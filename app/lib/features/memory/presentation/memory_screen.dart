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
  });

  final MemoryOverview overview;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final ValueChanged<MemoryItem> onEdit, onDelete;
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
                  ),
                  if (i < o.items.length - 1)
                    Divider(height: 1, color: AppColors.border, indent: 16),
                ],
              ],
            ),
          ),
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
  });
  final MemoryItem item;
  final bool busy;
  final VoidCallback onEdit, onDelete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.kindLabel, style: AppTypography.caption),
              Text(item.content, style: AppTypography.body),
            ],
          ),
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
