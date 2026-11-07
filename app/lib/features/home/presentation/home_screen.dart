import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../auth/application/auth_controller.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../../profile/application/profile_controller.dart';
import '../../today/presentation/today_section.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final onboarding = ref.watch(onboardingControllerProvider).value;
    final profile = ref.watch(profileControllerProvider).value;
    final name = auth is AuthAuthenticated ? auth.user.name : '';
    return PageScaffold(
      showBack: false,
      actions: [IconButton(tooltip: 'Buka profil', onPressed: () => context.go(Routes.profile), icon: const Icon(Icons.account_circle_outlined))],
      children: [
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
        const TodaySection(),
      ],
    );
  }
}
