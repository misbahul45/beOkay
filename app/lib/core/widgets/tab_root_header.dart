import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../format/greeting.dart';
import '../router/routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

class ProfileAction extends ConsumerWidget {
  const ProfileAction({super.key});

  static const label = 'Profil';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final name = auth is AuthAuthenticated ? firstName(auth.user.name) : '';
    final initial = name.isEmpty ? '' : name.characters.first.toUpperCase();
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: () => context.go(Routes.profile),
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: () => context.go(Routes.profile),
          radius: AppSpacing.minTouchTarget / 2,
          child: SizedBox.square(
            dimension: AppSpacing.minTouchTarget,
            child: Center(
              child: Container(
                height: 36,
                width: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
                child: initial.isEmpty
                    ? Icon(
                        Icons.person_outline_rounded,
                        size: 20,
                        color: AppColors.brand,
                      )
                    : Text(
                        initial,
                        style: AppTypography.secondaryStrong.copyWith(
                          color: AppColors.brand,
                          fontSize: 14,
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

class TabRootHeader extends StatelessWidget {
  const TabRootHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: AppTypography.headline),
              ),
            ),
            const ProfileAction(),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(subtitle!, style: AppTypography.secondary),
        ],
      ],
    );
  }
}
