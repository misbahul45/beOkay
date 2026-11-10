import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

class NavItem {
  const NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class NavCenterAction {
  const NavCenterAction({
    required this.label,
    required this.onPressed,
    this.icon = Icons.add_rounded,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

class PillNavBar extends StatelessWidget {
  const PillNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.centerAction,
  });

  final List<NavItem> items;
  final int? currentIndex;
  final ValueChanged<int> onTap;

  final NavCenterAction? centerAction;

  static const double _barHeight = 68;

  Widget _label(String text, {required bool on}) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(
      text,
      maxLines: 1,
      style: AppTypography.caption.copyWith(
        fontSize: 11,
        color: on ? AppColors.brand : AppColors.textSecondary,
        fontWeight: on ? FontWeight.w700 : FontWeight.w500,
      ),
    ),
  );

  Widget _item(int index) {
    final on = index == currentIndex;
    return Expanded(
      child: Semantics(
        button: true,
        selected: on,
        label: items[index].label,
        excludeSemantics: true,
        onTap: () => onTap(index),
        child: InkResponse(
          onTap: () => onTap(index),
          highlightShape: BoxShape.rectangle,
          radius: 32,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 28,
                width: 52,
                decoration: BoxDecoration(
                  color: on ? AppColors.brandTint : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  on ? items[index].selectedIcon : items[index].icon,
                  color: on ? AppColors.brand : AppColors.textSecondary,
                  size: 21,
                ),
              ),
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _label(items[index].label, on: on),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _center(NavCenterAction a) => SizedBox(
    width: 72,
    child: Semantics(
      button: true,
      label: a.label,
      excludeSemantics: true,
      onTap: a.onPressed,
      child: InkResponse(
        onTap: a.onPressed,
        radius: 36,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 40,
              width: 40,
              decoration: const BoxDecoration(
                color: AppColors.brand,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x3316796F),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(a.icon, color: AppColors.onPrimary, size: 26),
            ),
            const SizedBox(height: 3),
            _label(a.label, on: true),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Container(
            height: _barHeight,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(_barHeight / 2),
              border: Border.all(color: AppColors.border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A18252A),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  if (centerAction != null && index == items.length ~/ 2)
                    _center(centerAction!),
                  _item(index),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
