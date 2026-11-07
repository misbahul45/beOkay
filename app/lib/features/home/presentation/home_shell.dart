import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/pill_nav_bar.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.child});

  final Widget child;

  static const _items = [
    NavItem(label: 'Beranda', icon: Icons.home_outlined, selectedIcon: Icons.home_rounded),
    NavItem(label: 'Profil', icon: Icons.person_outline, selectedIcon: Icons.person_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = location.startsWith(Routes.profile) ? 1 : 0;
    return Scaffold(
      body: child,
      bottomNavigationBar: PillNavBar(
        items: _items,
        currentIndex: index,
        onTap: (value) => context.go(value == 0 ? Routes.home : Routes.profile),
      ),
    );
  }
}
