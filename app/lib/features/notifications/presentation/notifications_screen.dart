import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../application/realtime_controller.dart';
import '../data/notification_repository.dart';
import 'notification_widgets.dart';

String dayHeading(DateTime t, DateTime now) {
  final d = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return 'Hari ini';
  if (diff == 1) return 'Kemarin';
  return DateFormat('EEEE, d MMM', 'id_ID').format(t);
}

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  final extra = <AppNotification>[];
  final readNow = <String>{};
  String? cursor;
  bool loadingMore = false;

  Future<void> _open(AppNotification n) async {
    final repo = ref.read(notificationRepositoryProvider);
    if (!n.read && !readNow.contains(n.id)) {
      setState(() => readNow.add(n.id));
      try {
        ref
            .read(realtimeProvider.notifier)
            .setUnread(await repo.markRead(n.id));
      } catch (_) {}
    }
    final route = routeForAction(n.action, n.refId);
    if (route != null && mounted) context.push(route);
  }

  Future<void> _readAll() async {
    try {
      await ref.read(notificationRepositoryProvider).markAllRead();
      ref.read(realtimeProvider.notifier).setUnread(0);
      extra.clear();
      cursor = null;
      ref.invalidate(notificationsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(messageFor(e))));
      }
    }
  }

  Future<void> _more(String next) async {
    setState(() => loadingMore = true);
    try {
      final page = await ref
          .read(notificationRepositoryProvider)
          .list(cursor: next);
      setState(() {
        extra.addAll(page.items);
        cursor = page.nextCursor;
      });
    } finally {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(notificationsProvider);
    final live = ref.watch(realtimeProvider);
    return PageScaffold(
      title: 'Notifikasi',
      actions: [
        if (live.unread > 0)
          TextButton(onPressed: _readAll, child: const Text('Tandai dibaca')),
      ],
      onRefresh: () async {
        extra.clear();
        cursor = null;
        ref.invalidate(notificationsProvider);
        await ref
            .read(notificationsProvider.future)
            .then<void>((_) {}, onError: (_) {});
      },
      children: [
        Row(
          children: [
            Container(
              height: 8,
              width: 8,
              decoration: BoxDecoration(
                color: live.connected ? AppColors.leaf : AppColors.disabled,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                live.connected
                    ? 'Terhubung · pembaruan langsung'
                    : 'Menyambungkan pembaruan langsung…',
                style: AppTypography.caption,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        value.when(
          loading: () => const SkeletonList(rows: 4),
          error: (e, _) => ErrorState(
            error: e,
            onRetry: () => ref.invalidate(notificationsProvider),
          ),
          data: (page) {
            final items = [
              for (final n in [...page.items, ...extra])
                readNow.contains(n.id)
                    ? AppNotification.fromJson({
                        'id': n.id,
                        'kind': n.kind,
                        'title': n.title,
                        'body': n.body,
                        'action': n.action,
                        'refId': n.refId,
                        'read': true,
                        'createdAt': n.createdAt.toUtc().toIso8601String(),
                      })
                    : n,
            ];
            final next = extra.isEmpty ? page.nextCursor : cursor;
            if (items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Column(
                  children: [
                    Icon(
                      Icons.notifications_none_rounded,
                      size: 40,
                      color: AppColors.decorative,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Belum ada notifikasi. Pengingat, rencana kecil, refleksi, dan kabar tantangan akan muncul di sini.',
                      style: AppTypography.secondary,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }
            final now = DateTime.now();
            final children = <Widget>[];
            String? last;
            for (final n in items) {
              final h = dayHeading(n.createdAt, now);
              if (h != last) {
                children.add(
                  Padding(
                    padding: EdgeInsets.only(
                      left: 4,
                      top: last == null ? 0 : AppSpacing.md,
                      bottom: AppSpacing.xs,
                    ),
                    child: Semantics(
                      header: true,
                      child: Text(
                        h.toUpperCase(),
                        style: AppTypography.overline,
                      ),
                    ),
                  ),
                );
                last = h;
              }
              children.add(
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: NotificationTile(item: n, onTap: () => _open(n)),
                ),
              );
            }
            if (next != null) {
              children.add(
                Center(
                  child: TextButton(
                    onPressed: loadingMore ? null : () => _more(next),
                    child: const Text('Muat lebih banyak'),
                  ),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        Material(
          color: AppColors.surfaceMuted,
          borderRadius: AppRadius.cardRadius,
          child: ListTile(
            leading: Icon(Icons.tune, color: AppColors.brand),
            title: Text(
              'Atur jenis notifikasi dan push',
              style: AppTypography.bodyStrong,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(Routes.notificationSettings),
          ),
        ),
      ],
    );
  }
}

const notificationKindLabels = {
  'REMINDER': ('Pengingat', 'Waktu mencatat yang kamu atur'),
  'COACHING': ('Rencana kecil', 'Pengingat dari rencana yang kamu terima'),
  'REFLECTION': ('Refleksi mingguan', 'Saat refleksi minggu ini siap'),
  'CHALLENGE': ('Tantangan', 'Tantangan dimulai dan hasilnya'),
  'RECOGNITION': ('Pencapaian', 'Pengakuan usaha pribadi'),
};

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  bool busy = false;

  Future<void> _update({bool? push, Set<String>? muted}) async {
    setState(() => busy = true);
    try {
      await ref
          .read(notificationRepositoryProvider)
          .updatePreferences(pushEnabled: push, mutedKinds: muted);
      ref.invalidate(notificationPreferencesProvider);
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
    final value = ref.watch(notificationPreferencesProvider);
    return PageScaffold(
      title: 'Pengaturan notifikasi',
      children: [
        value.when(
          loading: () => const SkeletonList(rows: 3),
          error: (e, _) => ErrorState(
            error: e,
            onRetry: () => ref.invalidate(notificationPreferencesProvider),
          ),
          data: (p) {
            final pushNote = !p.pushConfigured
                ? 'Push belum tersedia di server ini; notifikasi tetap masuk ke kotak masuk.'
                : p.devices == 0
                ? 'Belum ada perangkat terdaftar untuk push. Notifikasi tetap masuk ke kotak masuk.'
                : 'Teks layar kunci selalu umum, tanpa nilai kesehatan.';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Material(
                  color: AppColors.surface,
                  borderRadius: AppRadius.cardRadius,
                  clipBehavior: Clip.antiAlias,
                  child: SwitchListTile(
                    value: p.pushEnabled,
                    onChanged: busy ? null : (v) => _update(push: v),
                    title: Text(
                      'Notifikasi push',
                      style: AppTypography.bodyStrong,
                    ),
                    subtitle: Text(pushNote, style: AppTypography.caption),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    'JENIS NOTIFIKASI',
                    style: AppTypography.overline,
                  ),
                ),
                Material(
                  color: AppColors.surface,
                  borderRadius: AppRadius.cardRadius,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final e in notificationKindLabels.entries)
                        SwitchListTile(
                          value: !p.mutedKinds.contains(e.key),
                          onChanged: busy
                              ? null
                              : (on) => _update(
                                  muted: on
                                      ? ({...p.mutedKinds}..remove(e.key))
                                      : {...p.mutedKinds, e.key},
                                ),
                          secondary: Icon(
                            notificationStyle(e.key).icon,
                            color: notificationStyle(e.key).ink,
                          ),
                          title: Text(e.value.$1, style: AppTypography.body),
                          subtitle: Text(
                            e.value.$2,
                            style: AppTypography.caption,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Jenis yang dimatikan tidak lagi dibuat, termasuk di kotak masuk.',
                  style: AppTypography.caption,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
