import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/error_messages.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
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
              Text('beOkay', style: AppTypography.headline),
              const SizedBox(height: AppSpacing.lg),
              if (problem == null)
                Semantics(label: 'Memuat', child: const SizedBox(height: 28, width: 28, child: CircularProgressIndicator(strokeWidth: 2.6, color: AppColors.primary)))
              else ...[
                Text(problem, textAlign: TextAlign.center, style: AppTypography.secondary),
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
