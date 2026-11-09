import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/routes.dart';
import '../../../core/format/greeting.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/beokay_avatar.dart';
import '../../medication/application/medication_controller.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../auth/application/auth_controller.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../../profile/application/profile_controller.dart';
import '../../quick_record/presentation/quick_record_sheet.dart';
import '../../today/application/today_controller.dart';
import '../../today/presentation/today_section.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final onboarding = ref.watch(onboardingControllerProvider).value;
    final profile = ref.watch(profileControllerProvider).value;
    final today = ref.watch(todayProvider).value;
    final name = auth is AuthAuthenticated ? auth.user.name : '';
    final consentBlocked = onboarding?.requiresConsentReview == true;

    return PageScaffold(
      showBack: false,
      onRefresh: () async {
        ref.invalidate(todayProvider);
        await ref.read(todayProvider.future).catchError((_) => null);
      },
      actions: [
        IconButton(
          tooltip: 'Buka profil',
          constraints: const BoxConstraints(
            minWidth: AppSpacing.minTouchTarget,
            minHeight: AppSpacing.minTouchTarget,
          ),
          onPressed: () => context.go(Routes.profile),
          icon: const Icon(Icons.account_circle_outlined, size: 28),
        ),
      ],
      children: [
        Builder(
          builder: (context) {
            final unconfirmed = ref.watch(medicationTodayProvider).value?.unknown ?? 0;
            final message = greetingFor(
              now: DateTime.now(),
              name: name,
              unconfirmedMedications: unconfirmed,
              noMealToday: today?.nutrition != null && today!.nutrition!.mealCount == 0,
            );
            return Semantics(
              header: true,
              child: AvatarGreeting(message: (title: message.title, detail: message.detail)),
            );
          },
        ),
        if (today != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${DateFormat('EEEE, d MMMM y', 'id_ID').format(DateTime.parse(today.date))} · ${today.timezone}',
            style: AppTypography.caption,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        if (!consentBlocked) ...[
          PillButton(
            label: 'Quick Record',
            icon: Icons.add_rounded,
            onPressed: () => showQuickRecord(context),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (consentBlocked) ...[
          InfoCard(
            tone: InfoTone.warning,
            title: 'Persetujuan perlu ditinjau',
            text:
                'Sebagian persetujuan wajib belum aktif, jadi fitur yang memproses data kesehatan dihentikan sementara.',
            action: PillButton(
              label: 'Tinjau persetujuan',
              kind: PillButtonKind.secondary,
              expand: false,
              onPressed: () => context.push(Routes.consentManagement),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (profile != null && !profile.isComplete) ...[
          InfoCard(
            title: 'Lengkapi profilmu',
            text:
                'Tahun lahir belum diisi. Ini opsional, tetapi membantu menyesuaikan pengalaman.',
            action: PillButton(
              label: 'Lengkapi',
              kind: PillButtonKind.secondary,
              expand: false,
              onPressed: () => context.push(Routes.editProfile),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        const TodaySection(),
      ],
    );
  }
}
