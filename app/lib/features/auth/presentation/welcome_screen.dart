import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/beokay_avatar.dart';
import '../../../core/widgets/pill_button.dart';

/// First screen: the avatar introduces itself. Short copy; the action is one tap away.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0E6B73), Color(0xFF16796F), Color(0xFF07313B)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.md,
              AppSpacing.page,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(flex: 2),
                const Center(child: BeOkayAvatar(size: 132)),
                const SizedBox(height: AppSpacing.xl),
                Semantics(
                  header: true,
                  child: Text(
                    'Halo, aku beOkay.',
                    style: AppTypography.display.copyWith(color: Colors.white),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Teman catatan kesehatan harianmu.',
                  style: AppTypography.body.copyWith(
                    color: const Color(0xFFCFE8E4),
                  ),
                ),
                const Spacer(flex: 3),
                PillButton(
                  label: 'Mulai Sekarang',
                  kind: PillButtonKind.light,
                  onPressed: () => context.go(Routes.register),
                ),
                const SizedBox(height: AppSpacing.xs),
                PillButton(
                  label: 'Coba dulu tanpa akun',
                  kind: PillButtonKind.secondary,
                  onPressed: () => context.go(Routes.guest),
                ),
                const SizedBox(height: 4),
                Text(
                  'Mode coba menyimpan catatan hanya di ponsel ini selama 7 hari.',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption.copyWith(
                    color: const Color(0xFFCFE8E4),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Center(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.transparent,
                    ),
                    onPressed: () => context.go(Routes.login),
                    child: Text(
                      'Sudah punya akun? Masuk',
                      style: AppTypography.bodyStrong.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
