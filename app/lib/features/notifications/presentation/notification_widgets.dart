import '../../../core/a11y/announce.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../application/realtime_controller.dart';
import '../data/notification_repository.dart';

({IconData icon, Color tint, Color ink}) notificationStyle(String kind) =>
    switch (kind) {
      'REMINDER' => (
        icon: Icons.alarm_rounded,
        tint: AppColors.mealTint,
        ink: AppColors.mealInk,
      ),
      'COACHING' => (
        icon: Icons.directions_walk_rounded,
        tint: AppColors.activityTint,
        ink: AppColors.activityInk,
      ),
      'REFLECTION' => (
        icon: Icons.auto_awesome,
        tint: AppColors.brandTint,
        ink: AppColors.brand,
      ),
      'CHALLENGE' => (
        icon: Icons.flag_outlined,
        tint: AppColors.goalTint,
        ink: AppColors.goalInk,
      ),
      _ => (
        icon: Icons.emoji_events_outlined,
        tint: AppColors.glucoseTint,
        ink: AppColors.glucoseInk,
      ),
    };

class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  static const label = 'Notifikasi';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(realtimeProvider.select((s) => s.unread));
    return Semantics(
      button: true,
      label: unread > 0 ? '$label, $unread belum dibaca' : label,
      excludeSemantics: true,
      onTap: () => context.push(Routes.notifications),
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: () => context.push(Routes.notifications),
          radius: AppSpacing.minTouchTarget / 2,
          child: SizedBox.square(
            dimension: AppSpacing.minTouchTarget,
            child: Center(
              child: Badge(
                isLabelVisible: unread > 0,
                label: Text(unread > 9 ? '9+' : '$unread'),
                child: Container(
                  height: 36,
                  width: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Icon(
                    unread > 0
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_none_rounded,
                    size: 20,
                    color: AppColors.brand,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NotificationTile extends StatelessWidget {
  const NotificationTile({super.key, required this.item, required this.onTap});

  final AppNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = notificationStyle(item.kind);
    final time = TimeOfDay.fromDateTime(item.createdAt);
    final clock =
        '${time.hour.toString().padLeft(2, '0')}.${time.minute.toString().padLeft(2, '0')}';
    return Semantics(
      button: true,
      label:
          '${item.read ? '' : 'Belum dibaca. '}${item.title}. ${item.body}. $clock',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: item.read ? AppColors.surface : AppColors.brandTint,
        borderRadius: AppRadius.cardRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 36,
                  width: 36,
                  decoration: BoxDecoration(
                    color: item.read ? s.tint : AppColors.surface,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(s.icon, size: 18, color: s.ink),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: item.read
                            ? AppTypography.body.copyWith(
                                fontWeight: FontWeight.w500,
                              )
                            : AppTypography.bodyStrong,
                      ),
                      Text(item.body, style: AppTypography.secondary),
                      const SizedBox(height: 2),
                      Text(clock, style: AppTypography.caption),
                    ],
                  ),
                ),
                if (!item.read)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 6),
                    child: Container(
                      height: 8,
                      width: 8,
                      decoration: BoxDecoration(
                        color: AppColors.brand,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void showNotificationBanner(
  BuildContext context,
  AppNotification n,
  VoidCallback onOpen,
) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final s = notificationStyle(n.kind);
  announce(context, 'Notifikasi baru: ${n.title}. ${n.body}');
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
      content: Row(
        children: [
          Icon(s.icon, color: AppColors.onPrimary, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  n.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
      action: SnackBarAction(label: 'Buka', onPressed: onOpen),
    ),
  );
}
