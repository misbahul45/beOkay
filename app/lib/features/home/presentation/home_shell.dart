import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/pill_nav_bar.dart';
import '../../notifications/application/realtime_controller.dart';
import '../../notifications/presentation/notification_widgets.dart';
import '../../push/data/push_client.dart';
import '../../quick_record/presentation/quick_record_sheet.dart';
import '../../reminders/application/reminders_controller.dart';
import '../../sync/presentation/sync_banner.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.child});

  final Widget child;

  static const _items = [
    NavItem(
      label: 'Beranda',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    NavItem(
      label: 'Catatan',
      icon: Icons.edit_note_outlined,
      selectedIcon: Icons.edit_note_rounded,
    ),
    NavItem(
      label: 'Asisten',
      icon: Icons.auto_awesome_outlined,
      selectedIcon: Icons.auto_awesome,
    ),
    NavItem(
      label: 'Wawasan',
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights_rounded,
    ),
  ];

  static const _routes = [
    Routes.home,
    Routes.log,
    Routes.coach,
    Routes.insights,
  ];

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  StreamSubscription<Map<String, dynamic>>? _opened;

  @override
  void initState() {
    super.initState();
    unawaited(_listenPushOpens());
  }

  Future<void> _listenPushOpens() async {
    final client = ref.read(pushClientProvider);
    try {
      if (!await client.available() || !mounted) return;
      final first = await client.openedAtLaunch();
      if (first != null) _openFromPush(first);
      if (!mounted) return;
      _opened = client.onOpened.listen(_openFromPush);
    } catch (_) {}
  }

  void _openFromPush(Map<String, dynamic> data) {
    if (!mounted) return;
    final route = routeForAction(
      '${data['action'] ?? ''}',
      (data['refId'] as String?)?.isEmpty ?? true
          ? null
          : data['refId'] as String,
    );
    context.push(route ?? Routes.notifications);
  }

  @override
  void dispose() {
    _opened?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(reminderSyncProvider);
    ref.watch(realtimeProvider.select((s) => s.connected));
    ref.listen(latestNotificationProvider, (_, n) {
      if (n == null) return;
      showNotificationBanner(context, n, () {
        final route = routeForAction(n.action, n.refId);
        context.push(route ?? Routes.notifications);
      });
      ref.read(latestNotificationProvider.notifier).clear();
    });
    final location = GoRouterState.of(context).uri.path;
    final found = HomeShell._routes.indexWhere(
      (route) => location.startsWith(route),
    );
    return Scaffold(
      body: Column(
        children: [
          const SyncBanner(),
          Expanded(child: widget.child),
        ],
      ),
      bottomNavigationBar: PillNavBar(
        items: HomeShell._items,
        currentIndex: found < 0 ? null : found,
        onTap: (value) => context.go(HomeShell._routes[value]),
        centerAction: NavCenterAction(
          label: 'Catat',
          onPressed: () => showQuickRecord(context),
        ),
      ),
    );
  }
}

class BackToHome extends StatelessWidget {
  const BackToHome({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: GoRouter.of(context).canPop(),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) context.go(Routes.home);
    },
    child: child,
  );
}
