import '../../guest/guest_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/routes.dart';
import '../../../core/format/greeting.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../notifications/presentation/notification_widgets.dart';
import '../../community/application/community_controller.dart';
import '../../community/presentation/community_highlight_card.dart';
import '../../../core/widgets/tab_root_header.dart';
import '../../interventions/presentation/intervention_card.dart';
import '../../next_action/application/next_action_controller.dart';
import '../../next_action/presentation/next_action_section.dart';
import '../../medication/application/medication_controller.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/pill_button.dart';
import '../../auth/application/auth_controller.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../../profile/application/profile_controller.dart';
import '../../today/application/today_controller.dart';
import '../../today/presentation/today_section.dart';
import '../../quick_record/presentation/quick_record_sheet.dart';
import '../../quick_record/application/quick_record_controller.dart';
import '../../quick_record/presentation/quick_repeat_card.dart';
import '../../clinical/presentation/hba1c_due_card.dart';
import '../../feature_flags/feature_flags.dart';

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
        ref.invalidate(nextActionProvider);
        ref.invalidate(homeHighlightProvider);
        ref.invalidate(quickSuggestionsProvider);
        ref.invalidate(featuresProvider);
        await ref.read(todayProvider.future).catchError((_) => null);
      },
      children: [
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
            final date = today == null
                ? null
                : DateFormat(
                    'EEEE, d MMMM',
                    'id_ID',
                  ).format(DateTime.parse(today.date));
            return _HomeHeader(
              greeting: [message.title, ?date].join(' · '),
              detail: message.detail,
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
        if (!consentBlocked) const NextActionSection(),
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
        const GuestImportCard(),
        const _QuickLaunch(),
        if (!consentBlocked) const QuickRepeatCard(),
        if (!consentBlocked) const Hba1cDueCard(),
        const TodaySection(),
        if (!consentBlocked &&
            featureOn(ref.watch(featuresProvider).value, 'community'))
          const CommunityHighlightCard(),
      ],
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.greeting, this.detail});

  final String greeting;
  final String? detail;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text('Beranda', style: AppTypography.headline),
            ),
          ),
          const NotificationBell(),
          const ProfileAction(),
        ],
      ),
      Text(greeting, style: AppTypography.secondary),
      if (detail case final d? when d.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs),
          child: Text(d, style: AppTypography.secondary),
        ),
    ],
  );
}

class _QuickLaunch extends StatefulWidget {
  const _QuickLaunch();
  @override
  State<_QuickLaunch> createState() => _QuickLaunchState();
}

class _QuickLaunchState extends State<_QuickLaunch> {
  bool done = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (done) return;
    final quick = GoRouterState.of(context).uri.queryParameters['quick'] == '1';
    if (!quick) return;
    done = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(Routes.home);
      showQuickRecord(context);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
