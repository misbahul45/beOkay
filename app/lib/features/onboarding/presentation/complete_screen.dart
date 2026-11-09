import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/error_messages.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/beokay_avatar.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../application/onboarding_controller.dart';

class OnboardingCompleteScreen extends ConsumerStatefulWidget {
  const OnboardingCompleteScreen({super.key});

  @override
  ConsumerState<OnboardingCompleteScreen> createState() => _OnboardingCompleteScreenState();
}

class _OnboardingCompleteScreenState extends ConsumerState<OnboardingCompleteScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _finish() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(onboardingControllerProvider.notifier).complete();
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
      bottom: PillButton(label: 'Masuk ke Beranda', loading: _loading, onPressed: _finish),
      children: [
        const SizedBox(height: AppSpacing.giant),
        const Center(child: BeOkayAvatar(size: 112)),
        const SizedBox(height: AppSpacing.xl),
        Semantics(header: true, child: Text('Semua siap!', textAlign: TextAlign.center, style: AppTypography.headline)),
        const SizedBox(height: AppSpacing.sm),
        Text('Yuk mulai mencatat.', textAlign: TextAlign.center, style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
        if (_error != null) ...[const SizedBox(height: AppSpacing.md), ErrorBanner(_error!)],
      ],
    );
  }
}
