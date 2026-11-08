import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/verify_email_screen.dart';
import '../../features/auth/presentation/welcome_screen.dart';
import '../../features/consent/presentation/consent_management_screen.dart';
import '../../features/consent/presentation/consent_screen.dart';
import '../../features/health_profile/presentation/health_profile_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/home/presentation/home_shell.dart';
import '../../features/home/presentation/splash_screen.dart';
import '../../features/onboarding/application/onboarding_controller.dart';
import '../../features/onboarding/presentation/complete_screen.dart';
import '../../features/onboarding/presentation/intro_screen.dart';
import '../../features/preferences/presentation/preferences_setup_screen.dart';
import '../../features/profile/presentation/personal_profile_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/settings/presentation/account_security_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/nutrition/presentation/meal_history_screen.dart';
import '../../features/nutrition/presentation/meal_form_screen.dart';
import '../../features/nutrition/presentation/meal_detail_screen.dart';
import 'redirect.dart';
import 'routes.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.listen(onboardingControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final onboarding = ref.read(onboardingControllerProvider);
      final load = onboarding.when(
        data: (_) => OnboardingLoad.ready,
        loading: () => OnboardingLoad.loading,
        error: (_, _) => OnboardingLoad.error,
      );
      return computeRedirect(
        auth: ref.read(authControllerProvider),
        onboardingLoad: load,
        onboarding: onboarding.value,
        location: state.uri.toString(),
      );
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: Routes.register, builder: (_, _) => const RegisterScreen()),
      GoRoute(path: Routes.login, builder: (_, state) => LoginScreen(initialEmail: state.uri.queryParameters['email'])),
      GoRoute(path: Routes.verifyEmail, builder: (_, state) => VerifyEmailScreen(email: state.uri.queryParameters['email'] ?? '')),
      GoRoute(path: Routes.forgotPassword, builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(path: Routes.onboardingIntro, builder: (_, _) => const OnboardingIntroScreen()),
      GoRoute(path: Routes.onboardingConsent, builder: (_, _) => const ConsentScreen()),
      GoRoute(path: Routes.onboardingProfile, builder: (_, _) => const PersonalProfileScreen(onboarding: true)),
      GoRoute(path: Routes.onboardingHealth, builder: (_, _) => const HealthProfileScreen(onboarding: true)),
      GoRoute(path: Routes.onboardingPreferences, builder: (_, _) => const PreferencesSetupScreen()),
      GoRoute(path: Routes.onboardingComplete, builder: (_, _) => const OnboardingCompleteScreen()),
      ShellRoute(
        builder: (_, _, child) => HomeShell(child: child),
        routes: [
          GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
          GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen()),
        ],
      ),
      GoRoute(path: Routes.editProfile, builder: (_, _) => const PersonalProfileScreen(onboarding: false)),
      GoRoute(path: Routes.meals, builder: (_, _) => const MealHistoryScreen()),
      GoRoute(path: Routes.addMeal, builder: (_, _) => const MealFormScreen()),
      GoRoute(path: '/meals/:id/edit', builder: (_, state) => MealDetailScreen(id: state.pathParameters['id']!,edit:true)),
      GoRoute(path: '/meals/:id', builder: (_, state) => MealDetailScreen(id: state.pathParameters['id']!)),
      GoRoute(path: Routes.editHealth, builder: (_, _) => const HealthProfileScreen(onboarding: false)),
      GoRoute(path: Routes.settings, builder: (_, _) => const SettingsScreen()),
      GoRoute(path: Routes.consentManagement, builder: (_, _) => const ConsentManagementScreen()),
      GoRoute(path: Routes.accountSecurity, builder: (_, _) => const AccountSecurityScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
