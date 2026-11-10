import '../../features/auth/application/auth_controller.dart';
import '../../features/onboarding/data/onboarding_status.dart';
import 'routes.dart';

String routeForOnboarding(OnboardingState state) => switch (state) {
  OnboardingState.emailVerificationPending => Routes.verifyEmail,
  OnboardingState.notStarted => Routes.onboardingIntro,
  OnboardingState.consentPending => Routes.onboardingConsent,
  OnboardingState.personalProfilePending => Routes.onboardingProfile,
  OnboardingState.healthProfilePending => Routes.onboardingHealth,
  OnboardingState.preferencesPending => Routes.onboardingPreferences,
  OnboardingState.readyToComplete => Routes.onboardingComplete,
  OnboardingState.completed => Routes.home,
};

enum OnboardingLoad { loading, error, ready }

String? computeRedirect({
  required AuthState auth,
  required OnboardingLoad onboardingLoad,
  required OnboardingStatus? onboarding,
  required String location,
}) {
  final path = Uri.parse(location).path;
  String? go(String target) => path == target ? null : target;

  switch (auth) {
    case AuthLoading() || AuthUnavailable():
      return go(Routes.splash);
    case AuthUnauthenticated(:final sessionExpired):
      return Routes.publicRoutes.contains(path)
          ? null
          : go(sessionExpired ? Routes.login : Routes.welcome);
    case AuthAuthenticated():
      break;
  }

  if (onboardingLoad != OnboardingLoad.ready || onboarding == null) {
    return go(Routes.splash);
  }

  final target = routeForOnboarding(onboarding.state);
  if (onboarding.isCompleted) {
    final leaving =
        path == Routes.splash ||
        Routes.publicRoutes.contains(path) ||
        Routes.onboardingSequence.contains(path);
    return leaving ? go(Routes.home) : null;
  }

  final requested = Routes.onboardingSequence.indexOf(path);
  final allowed = Routes.onboardingSequence.indexOf(target);
  if (requested != -1 && allowed != -1 && requested <= allowed) return null;
  return go(target);
}
