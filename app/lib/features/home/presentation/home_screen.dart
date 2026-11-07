import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../auth/application/auth_controller.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../../profile/application/profile_controller.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final onboarding = ref.watch(onboardingControllerProvider).value;
    final profile = ref.watch(profileControllerProvider).value;
    final name = auth is AuthAuthenticated ? auth.user.name : '';
    final today = DateFormat('EEEE, d MMMM y', 'id_ID').format(DateTime.now());
    return PageScaffold(
      showBack: false,
      children: [
        Text(today.toUpperCase(), style: AppTypography.overline),
        const SizedBox(height: AppSpacing.xxs),
        Semantics(header: true, child: Text(name.isEmpty ? 'Halo.' : 'Halo, $name.', style: AppTypography.headline)),
        const SizedBox(height: AppSpacing.xs),
        Text('Mulai dari hal yang penting.', style: AppTypography.secondary),
        const SizedBox(height: AppSpacing.lg),
        if (onboarding?.requiresConsentReview == true) ...[
          InfoCard(
            tone: InfoTone.warning,
            title: 'Persetujuan perlu ditinjau',
            text: 'Sebagian persetujuan wajib belum aktif, jadi fitur yang memproses data kesehatan dihentikan sementara.',
            action: PillButton(label: 'Tinjau persetujuan', kind: PillButtonKind.secondary, expand: false, onPressed: () => context.push(Routes.consentManagement)),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (profile != null && !profile.isComplete) ...[
          InfoCard(
            title: 'Lengkapi profilmu',
            text: 'Tahun lahir belum diisi. Ini opsional, tetapi membantu menyesuaikan pengalaman.',
            action: PillButton(label: 'Lengkapi', kind: PillButtonKind.secondary, expand: false, onPressed: () => context.push(Routes.editProfile)),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.cardRadius, boxShadow: AppShadows.soft),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                child: const ExcludeSemantics(child: Icon(Icons.edit_note_rounded, color: AppColors.primary)),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('Pencatatan belum tersedia', style: AppTypography.title),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Akunmu, persetujuan, profil, dan preferensi sudah siap. Pencatatan makanan, aktivitas, glukosa, dan obat akan hadir di versi berikutnya.',
                style: AppTypography.secondary,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
