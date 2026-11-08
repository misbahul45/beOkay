import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/editorial_photo.dart';
import '../../../core/widgets/pill_button.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Stack(
        children: [
          const Positioned.fill(child: EditorialPhoto(figureX: 0.7)),
          SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              height: 28,
                              width: 28,
                              decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
                              alignment: Alignment.center,
                              child: Container(height: 10, width: 10, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text('beOkay', style: AppTypography.title.copyWith(color: AppColors.onPrimary)),
                          ],
                        ),
                        const SizedBox(height: 120),
                        const Spacer(),
                        Semantics(
                          header: true,
                          child: Text(
                            'Kenali Tubuhmu.\nBangun Kebiasaan yang Lebih Baik.',
                            style: AppTypography.display.copyWith(color: AppColors.onPrimary),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Catat kebiasaan harian, pahami perkembangan kesehatanmu, dan temukan langkah yang sesuai untukmu.',
                          style: AppTypography.body.copyWith(color: const Color(0xFFDCE7F0)),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        PillButton(label: 'Mulai Sekarang', kind: PillButtonKind.light, onPressed: () => context.go(Routes.register)),
                        const SizedBox(height: AppSpacing.xs),
                        Center(
                          child: TextButton(
                            style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: AppColors.onPrimary, backgroundColor: Colors.transparent),
                            onPressed: () => context.go(Routes.login),
                            child: Text('Sudah punya akun? Masuk', style: AppTypography.bodyStrong.copyWith(color: AppColors.onPrimary)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
