import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/error_messages.dart';
import '../../../core/router/redirect.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/editorial_photo.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../application/onboarding_controller.dart';

class OnboardingIntroScreen extends ConsumerStatefulWidget {
  const OnboardingIntroScreen({super.key});

  @override
  ConsumerState<OnboardingIntroScreen> createState() => _OnboardingIntroScreenState();
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
      if (mounted && status != null) context.go(routeForOnboarding(status.state));
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
      bottom: PillButton(label: 'Lanjut', loading: _loading, onPressed: _continue),
      children: [
        SizedBox(
          height: 300,
          child: EditorialPhoto(
            radius: AppRadius.sheet,
            tone: 1,
            figureX: 0.8,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Semantics(
                  header: true,
                  child: Text(
                    'Lebih Paham,\nLebih Terarah.',
                    style: AppTypography.headline.copyWith(color: AppColors.onPrimary, fontSize: 32),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Mulai dengan informasi dasar agar pengalaman aplikasi sesuai dengan kebutuhanmu.', style: AppTypography.body),
        const SizedBox(height: AppSpacing.lg),
        const _IntroPoint(icon: Icons.verified_user_outlined, title: 'Kamu yang mengontrol datamu', text: 'Kamu memilih persetujuan, dan bisa menariknya kapan saja.'),
        const SizedBox(height: AppSpacing.sm),
        const _IntroPoint(icon: Icons.person_outline, title: 'Hanya yang diperlukan', text: 'Kami menanyakan informasi dasar saja. Sebagian besar boleh dikosongkan.'),
        const SizedBox(height: AppSpacing.sm),
        const _IntroPoint(icon: Icons.healing_outlined, title: 'Bukan diagnosis', text: 'beOkay membantu mencatat dan memahami kebiasaan. Tidak memberi diagnosis atau saran medis.'),
        if (_error != null) ...[const SizedBox(height: AppSpacing.md), ErrorBanner(_error!)],
      ],
    );
  }
}

class _IntroPoint extends StatelessWidget {
  const _IntroPoint({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.cardRadius, boxShadow: AppShadows.soft),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
            child: ExcludeSemantics(child: Icon(icon, size: 22, color: AppColors.primary)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.bodyStrong),
                const SizedBox(height: 2),
                Text(text, style: AppTypography.secondary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
