import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/routes.dart';
import '../../../core/format/greeting.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/adaptive_hero_card.dart';
import '../../../core/widgets/beokay_avatar.dart';
import '../../../core/widgets/beokay_logo.dart';
import '../../../core/widgets/tab_root_header.dart';
import '../../interventions/presentation/intervention_card.dart';
import '../../medication/application/medication_controller.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../auth/application/auth_controller.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../../profile/application/profile_controller.dart';
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
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  header: true,
                  child: const BeOkayLogo(height: 32),
                ),
              ),
            ),
            const ProfileAction(),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Builder(
          builder: (context) {
            final unconfirmed =
                ref.watch(medicationTodayProvider).value?.unknown ?? 0;
            final message = greetingFor(
              now: DateTime.now(),
              name: name,
              unconfirmedMedications: unconfirmed,
              noMealToday:
                  today?.nutrition != null && today!.nutrition!.mealCount == 0,
            );
            return AdaptiveHeroCard(
              kicker: today == null
                  ? null
                  : DateFormat(
                      'EEEE, d MMMM',
                      'id_ID',
                    ).format(DateTime.parse(today.date)),
              title: message.title,
              detail: message.detail,
              sparkState: consentBlocked ? SparkState.neutral : SparkState.idle,
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
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
        if (!consentBlocked) const InterventionCard(),
        if (profile != null && !profile.isComplete) ...[
          InfoCard(
            title: 'Lengkapi profilmu',
            text: 'Tahun lahir belum diisi (opsional).',
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
