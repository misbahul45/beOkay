import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/error_messages.dart';
import '../../../core/notifications/reminder_scheduler.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/choice_chips.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../push/application/push_controller.dart';
import '../application/reminders_controller.dart';
import '../data/reminders_repository.dart';

/// Pengingat lokal untuk mencatat. Server hanya menyimpan aturannya; notifikasi dijadwalkan di perangkat
/// dan teks layar kunci tidak memuat nama obat atau nilai kesehatan.
class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  Future<void> _changed(WidgetRef ref) async {
    ref.invalidate(remindersProvider);
    await ref.read(reminderSyncProvider.notifier).sync();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(remindersProvider);
    final repo = ref.watch(remindersRepositoryProvider);
    return PageScaffold(
      title: 'Pengingat',
      onBack: () =>
          context.canPop() ? context.pop() : context.go(Routes.profile),
      bottom: PillButton(
        label: 'Tambah pengingat',
        icon: Icons.add_rounded,
        onPressed: () => showReminderSheet(context, ref),
      ),
      onRefresh: () async => ref.invalidate(remindersProvider),
      children: [
        const _PushTile(),
        const SizedBox(height: AppSpacing.md),
        AsyncBody<ReminderRules>(
          value: rules,
          onRetry: () => ref.invalidate(remindersProvider),
          skeletonRows: 3,
          data: (data) => data.items.isEmpty
              ? EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'Belum ada pengingat',
                  message:
                      'Tambahkan pengingat untuk jam yang biasa kamu catat atau minum obat.',
                  actionLabel: 'Tambah pengingat',
                  onAction: () => showReminderSheet(context, ref),
                )
              : Column(
                  children: [
                    for (final r in data.items) ...[
                      _ReminderTile(
                        reminder: r,
                        onEdit: () =>
                            showReminderSheet(context, ref, initial: r),
                        onToggle: (v) async {
                          try {
                            await repo.update(r, {'enabled': v});
                            await _changed(ref);
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(messageFor(e))),
                              );
                            }
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({
    required this.reminder,
    required this.onEdit,
    required this.onToggle,
  });
  final Reminder reminder;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    borderRadius: AppRadius.cardRadius,
    clipBehavior: Clip.antiAlias,
    child: ListTile(
      onTap: onEdit,
      title: Text(
        '${reminder.localTime} · ${reminder.title}',
        style: AppTypography.bodyStrong,
      ),
      subtitle: Text(
        '${reminderKindLabels[reminder.kind] ?? reminder.kind} · ${reminder.daysLabel}',
        style: AppTypography.caption,
      ),
      trailing: Switch(value: reminder.enabled, onChanged: onToggle),
    ),
  );
}

Future<void> showReminderSheet(
  BuildContext context,
  WidgetRef ref, {
  Reminder? initial,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _ReminderSheet(ref: ref, initial: initial),
);

class _ReminderSheet extends StatefulWidget {
  const _ReminderSheet({required this.ref, this.initial});
  final WidgetRef ref;
  final Reminder? initial;
  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  late final title = TextEditingController(text: widget.initial?.title ?? '');
  late String kind = widget.initial?.kind ?? 'glucose';
  late String time = widget.initial?.localTime ?? '07:30';
  late Set<int> days = {
    ...(widget.initial?.daysOfWeek ?? [1, 2, 3, 4, 5, 6, 7]),
  };
  bool busy = false;
  Object? error;

  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  Future<void> pickTime() async {
    final parts = time.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(
        () => time =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
      );
    }
  }

  Future<void> save() async {
    final t = title.text.trim();
    if (t.isEmpty) {
      setState(() => error = 'Beri nama pengingat.');
      return;
    }
    if (days.isEmpty) {
      setState(() => error = 'Pilih minimal satu hari.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final repo = widget.ref.read(remindersRepositoryProvider);
      final sortedDays = days.toList()..sort();
      if (widget.initial == null) {
        await repo.create(
          kind: kind,
          title: t,
          localTime: time,
          days: sortedDays,
        );
        // Izin diminta saat pengingat pertama dibuat; penolakan tidak menggagalkan penyimpanan aturan.
        final granted = await widget.ref
            .read(reminderSchedulerProvider)
            .requestPermission()
            .catchError((_) => false);
        if (!granted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Pengingat tersimpan, tetapi notifikasi belum diizinkan di pengaturan perangkat.',
              ),
            ),
          );
        }
      } else {
        await repo.update(widget.initial!, {
          'title': t,
          'localTime': time,
          'daysOfWeek': sortedDays,
        });
      }
      widget.ref.invalidate(remindersProvider);
      await widget.ref.read(reminderSyncProvider.notifier).sync();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove() async {
    setState(() => busy = true);
    try {
      await widget.ref.read(remindersRepositoryProvider).update(
        widget.initial!,
        {'archived': true},
      );
      widget.ref.invalidate(remindersProvider);
      await widget.ref.read(reminderSyncProvider.notifier).sync();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      24,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              widget.initial == null ? 'Tambah pengingat' : 'Ubah pengingat',
              style: AppTypography.headline,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            children: [
              for (final e in reminderKindLabels.entries)
                PillChip(
                  label: e.value,
                  selected: kind == e.key,
                  onTap: busy || widget.initial != null
                      ? null
                      : () => setState(() => kind = e.key),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            label: 'Nama pengingat',
            hint: 'mis. Catat gula pagi',
            controller: title,
            maxLength: 80,
          ),
          const SizedBox(height: AppSpacing.xs),
          PillButton(
            label: 'Jam $time',
            kind: PillButtonKind.secondary,
            icon: Icons.schedule,
            onPressed: busy ? null : pickTime,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Hari', style: AppTypography.caption),
          Wrap(
            spacing: 8,
            children: [
              for (var d = 1; d <= 7; d++)
                PillChip(
                  label: weekdayShort[d - 1],
                  selected: days.contains(d),
                  onTap: busy
                      ? null
                      : () => setState(
                          () => days.contains(d) ? days.remove(d) : days.add(d),
                        ),
                ),
            ],
          ),
          if (error != null)
            ErrorBanner(
              error is String ? error.toString() : messageFor(error!),
            ),
          const SizedBox(height: AppSpacing.sm),
          PillButton(label: 'Simpan', loading: busy, onPressed: save),
          if (widget.initial != null) ...[
            const SizedBox(height: AppSpacing.xs),
            PillButton(
              label: 'Hapus pengingat',
              kind: PillButtonKind.danger,
              onPressed: busy ? null : remove,
            ),
          ],
        ],
      ),
    ),
  );
}

/// Saklar push. Tersembunyi bila Firebase belum terkonfigurasi untuk aplikasi ini.
class _PushTile extends ConsumerWidget {
  const _PushTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final push = ref.watch(pushControllerProvider);
    if (push.status == PushStatus.unavailable) return const SizedBox.shrink();
    final on = push.status == PushStatus.on;
    final ctl = ref.read(pushControllerProvider.notifier);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Material(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: Text(
                'Kirim lewat notifikasi push',
                style: AppTypography.bodyStrong,
              ),
              subtitle: Text(
                on
                    ? 'Server mengirim pengingat ke perangkat ini. Notifikasi lokal dimatikan agar tidak ganda.'
                    : 'Aktifkan agar pengingat tetap datang walau aplikasi atau perangkat dimulai ulang. Teks tetap umum.',
                style: AppTypography.caption,
              ),
              value: on,
              onChanged: (v) async {
                await (v ? ctl.enable() : ctl.disable());
                await ref.read(reminderSyncProvider.notifier).sync();
              },
            ),
            if (push.message != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(push.message!, style: AppTypography.caption),
              ),
          ],
        ),
      ),
    );
  }
}
