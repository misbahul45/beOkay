import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/pill_nav_bar.dart';

/// Primary navigation: Beranda · Catatan · Wawasan · Profil.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.child});

  final Widget child;

  static const _items = [
    NavItem(label: 'Beranda', icon: Icons.home_outlined, selectedIcon: Icons.home_rounded),
    NavItem(label: 'Catatan', icon: Icons.edit_note_outlined, selectedIcon: Icons.edit_note_rounded),
    NavItem(label: 'Wawasan', icon: Icons.insights_outlined, selectedIcon: Icons.insights_rounded),
    NavItem(label: 'Profil', icon: Icons.person_outline, selectedIcon: Icons.person_rounded),
  ];

  static const _routes = [Routes.home, Routes.log, Routes.insights, Routes.profile];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final found = _routes.indexWhere((route) => location.startsWith(route));
    return Scaffold(
      body: child,
      bottomNavigationBar: PillNavBar(
        items: _items,
        currentIndex: found < 0 ? 0 : found,
        onTap: (value) => context.go(_routes[value]),
      ),
    );
  }
}
