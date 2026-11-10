import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/pill_nav_bar.dart';
import '../../quick_record/presentation/quick_record_sheet.dart';
import '../../reminders/application/reminders_controller.dart';
import '../../sync/presentation/sync_banner.dart';

class HomeShell extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(
      reminderSyncProvider,
    ); // menjaga notifikasi lokal selaras selama sesi aktif
    final location = GoRouterState.of(context).uri.path;
    final found = _routes.indexWhere((route) => location.startsWith(route));
    return Scaffold(
      body: Column(
        children: [
          const SyncBanner(),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: PillNavBar(
        items: _items,
        currentIndex: found < 0 ? null : found,
        onTap: (value) => context.go(_routes[value]),
        centerAction: NavCenterAction(
          label: 'Catat',
          onPressed: () => showQuickRecord(context),
        ),
      ),
    );
  }
}
