abstract final class Routes {
  static const splash = '/splash';
  static const welcome = '/welcome';
  static const register = '/register';
  static const login = '/login';
  static const verifyEmail = '/verify-email';
  static const forgotPassword = '/forgot-password';

  static const onboardingIntro = '/onboarding/intro';
  static const onboardingConsent = '/onboarding/consent';
  static const onboardingProfile = '/onboarding/profile';
  static const onboardingHealth = '/onboarding/health';
  static const onboardingPreferences = '/onboarding/preferences';
  static const onboardingComplete = '/onboarding/complete';

  static const home = '/home';
  static const meals = '/meals';
  static const addMeal = '/meals/new';
  static const profile = '/profile';
  static const editProfile = '/profile/edit';
  static const editHealth = '/profile/health';
  static const settings = '/settings';
  static const consentManagement = '/settings/consent';
  static const accountSecurity = '/settings/security';

  static const publicRoutes = {welcome, register, login, verifyEmail, forgotPassword};

  static const onboardingSequence = [
    onboardingIntro,
    onboardingConsent,
    onboardingProfile,
    onboardingHealth,
    onboardingPreferences,
    onboardingComplete,
  ];
}
