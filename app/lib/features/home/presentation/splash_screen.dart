import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/error_messages.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/beokay_avatar.dart';
import '../../../core/widgets/beokay_logo.dart';
import '../../../core/widgets/pill_button.dart';
import '../../auth/application/auth_controller.dart';
import '../../onboarding/application/onboarding_controller.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final onboarding = ref.watch(onboardingControllerProvider);
    String? problem;
    VoidCallback? retry;
    if (auth is AuthUnavailable) {
      problem = auth.message;
      retry = () => ref.read(authControllerProvider.notifier).restore();
    } else if (onboarding.hasError) {
      problem = messageFor(onboarding.error!);
      retry = () => ref.invalidate(onboardingControllerProvider);
    }
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.page),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (problem == null) ...[
                const AvatarLoader(),
                const SizedBox(height: AppSpacing.lg),
                const BeOkayLogo(width: 150),
              ] else ...[
                const BeOkayAvatar(size: 72, animate: false),
                const SizedBox(height: AppSpacing.md),
                Text(
                  problem,
                  textAlign: TextAlign.center,
                  style: AppTypography.secondary,
                ),
                const SizedBox(height: AppSpacing.md),
                PillButton(label: 'Coba lagi', expand: false, onPressed: retry),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
