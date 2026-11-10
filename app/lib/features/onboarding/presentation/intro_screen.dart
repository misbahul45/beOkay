import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/error_messages.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/beokay_avatar.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../application/onboarding_controller.dart';

class OnboardingIntroScreen extends ConsumerStatefulWidget {
  const OnboardingIntroScreen({super.key});

  @override
  ConsumerState<OnboardingIntroScreen> createState() =>
      _OnboardingIntroScreenState();
}

class _OnboardingIntroScreenState extends ConsumerState<OnboardingIntroScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _continue() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(onboardingControllerProvider.notifier).markIntroSeen();
      final status = ref.read(onboardingControllerProvider).value;
      if (mounted && status != null) {
        context.go(routeForOnboarding(status.state));
      }
    } catch (error) {
      if (mounted) setState(() => _error = messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      showBack: false,
      bottom: PillButton(
        label: 'Lanjut',
        loading: _loading,
        onPressed: _continue,
      ),
      children: [
        const SizedBox(height: AppSpacing.lg),
        const Center(child: BeOkayAvatar(size: 104)),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          header: true,
          child: Text(
            'Halo! Yuk kenalan sebentar.',
            textAlign: TextAlign.center,
            style: AppTypography.headline,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Hanya beberapa langkah singkat.',
          textAlign: TextAlign.center,
          style: AppTypography.secondary,
        ),
        const SizedBox(height: AppSpacing.lg),
        const _IntroPoint(
          icon: Icons.verified_user_outlined,
          title: 'Kamu yang mengontrol datamu',
        ),
        const SizedBox(height: AppSpacing.xs + 2),
        const _IntroPoint(
          icon: Icons.edit_note_rounded,
          title: 'Sebagian besar boleh dikosongkan',
        ),
        const SizedBox(height: AppSpacing.xs + 2),
        const _IntroPoint(
          icon: Icons.healing_outlined,
          title: 'Bukan diagnosis atau saran medis',
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          ErrorBanner(_error!),
        ],
      ],
    );
  }
}

class _IntroPoint extends StatelessWidget {
  const _IntroPoint({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.cardPadding,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        children: [
          Container(
            height: 36,
            width: 36,
            decoration: const BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
            child: ExcludeSemantics(
              child: Icon(icon, size: 18, color: AppColors.primary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(title, style: AppTypography.bodyStrong)),
        ],
      ),
    );
  }
}
