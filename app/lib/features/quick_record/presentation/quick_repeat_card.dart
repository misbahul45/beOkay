import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/a11y/announce.dart';
import '../../../core/analytics/usage_tracker.dart';
import '../../../core/network/account_scoped_repository.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/domain_style.dart';
import '../../activity/application/activity_controller.dart';
import '../../nutrition/application/nutrition_controller.dart';
import '../../nutrition/data/nutrition_models.dart';
import '../../today/application/today_controller.dart';
import '../application/quick_record_controller.dart';
import '../data/quick_record_repository.dart';

class QuickRepeatCard extends ConsumerStatefulWidget {
  const QuickRepeatCard({
    super.key,
    this.maxMeals = 3,
    this.maxActivities = 2,
    this.onSaved,
  });
  final int maxMeals, maxActivities;
  final VoidCallback? onSaved;

  @override
  ConsumerState<QuickRepeatCard> createState() => _QuickRepeatCardState();
}

class _QuickRepeatCardState extends ConsumerState<QuickRepeatCard> {
  final shownAt = DateTime.now();
  String? busyKey;

  Future<void> _repeatMeal(QuickMeal m) async {
    final repo = ref.read(nutritionRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final id = newRecordId();
    setState(() => busyKey = m.key);
    try {
      final saved = await repo.save({
        'id': id,
        'category': m.template['category'],
        'consumedAt': DateTime.now().toUtc().toIso8601String(),
        'notes': null,
        'items': m.template['items'],
      });
      _announce('${mealCategories[m.category]} tersimpan');
      _after('meal');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Tersimpan: ${mealCategories[m.category]} · ${m.title}',
          ),
          action: SnackBarAction(
            label: 'Lihat',
            onPressed: () => router.push('${Routes.meals}/${saved.id}'),
          ),
        ),
      );
    } on QueuedOffline {
      _after('meal');
      messenger.showSnackBar(
        const SnackBar(content: Text(queuedOfflineMessage)),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(messageFor(e))));
    } finally {
      if (mounted) setState(() => busyKey = null);
    }
  }

  Future<void> _repeatActivity(QuickActivity a) async {
    final repo = ref.read(activityRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final start = DateTime.now().subtract(Duration(minutes: a.minutes));
    setState(() => busyKey = a.key);
    try {
      final saved = await repo.save({
        'id': newRecordId(),
        ...a.template,
        'startedAt': start.toUtc().toIso8601String(),
        'source': 'manual',
      });
      _announce('Aktivitas tersimpan');
      _after('activity');
      messenger.showSnackBar(
        SnackBar(
          content: Text('Tersimpan: ${a.title}, selesai barusan'),
          action: SnackBarAction(
            label: 'Lihat',
            onPressed: () => router.push('${Routes.activities}/${saved.id}'),
          ),
        ),
      );
    } on QueuedOffline {
      _after('activity');
      messenger.showSnackBar(
        const SnackBar(content: Text(queuedOfflineMessage)),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(messageFor(e))));
    } finally {
      if (mounted) setState(() => busyKey = null);
    }
  }

  void _after(String domain) {
    final tracker = ref.read(usageTrackerProvider);
    tracker.track('quick_repeat_used', domain: domain);
    tracker.formSaved(domain, DateTime.now().difference(shownAt), via: 'quick');
    ref.invalidate(todayProvider);
    ref.invalidate(quickSuggestionsProvider);
    widget.onSaved?.call();
  }

  void _announce(String text) {
    if (mounted) announce(context, text);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(quickSuggestionsProvider).value;
    if (s == null || s.isEmpty) return const SizedBox.shrink();
    final meals = s.meals.take(widget.maxMeals).toList();
    final acts = s.activities.take(widget.maxActivities).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text('Sering dicatat', style: AppTypography.heading),
          ),
          const SizedBox(height: 2),
          Text(
            'Satu ketukan menyimpan dengan waktu sekarang.',
            style: AppTypography.secondary,
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final m in meals)
            _RepeatRow(
              style: DomainStyle.meal,
              title: m.title,
              subtitle:
                  '${mealCategories[m.category] ?? m.category} · ${m.count}× dalam 30 hari${m.nutritionKnown ? '' : ' · sebagian gizi belum ada'}',
              busy: busyKey == m.key,
              onTap: busyKey == null ? () => _repeatMeal(m) : null,
            ),
          for (final a in acts)
            _RepeatRow(
              style: DomainStyle.activity,
              title: a.title,
              subtitle: '${a.count}× dalam 30 hari · dicatat selesai sekarang',
              busy: busyKey == a.key,
              onTap: busyKey == null ? () => _repeatActivity(a) : null,
            ),
        ],
      ),
    );
  }
}

class _RepeatRow extends StatelessWidget {
  const _RepeatRow({
    required this.style,
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.onTap,
  });
  final DomainStyle style;
  final String title, subtitle;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Semantics(
      button: true,
      label: 'Ulangi ${style.label.toLowerCase()}: $title. $subtitle',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        child: InkWell(
          borderRadius: AppRadius.cardRadius,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: style.tint,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(style.icon, color: style.ink),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AppTypography.bodyStrong),
                        Text(subtitle, style: AppTypography.caption),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  busy
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.replay_rounded, color: AppColors.brand),
                            const SizedBox(width: 4),
                            Text(
                              'Ulangi',
                              style: AppTypography.secondaryStrong.copyWith(
                                color: AppColors.brand,
                              ),
                            ),
                          ],
                        ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
