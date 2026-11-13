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
  static const log = '/log';
  static const insights = '/insights';
  static const meals = '/meals';
  static const addMeal = '/meals/new';
  static const glucose = '/glucose';
  static const addGlucose = '/glucose/new';
  static const activities = '/activities';
  static const addActivity = '/activities/new';
  static const activityWeek = '/activities/weekly';
  static const medications = '/medications';
  static const addMedication = '/medications/new';
  static const sync = '/sync';
  static const trends = '/trends';
  static const foodPreferences = '/profile/food-preferences';
  static const reminders = '/reminders';
  static const coach = '/coach';
  static const community = '/community';
  static const goals = '/goals';
  static const addGoal = '/goals/new';
  static const profile = '/profile';
  static const editProfile = '/profile/edit';
  static const editHealth = '/profile/health';
  static const journey = '/profile/journey';
  static const settings = '/settings';
  static const consentManagement = '/settings/consent';
  static const accountSecurity = '/settings/security';
  static const privacyData = '/settings/privacy';
  static const memory = '/settings/memory';
  static const coaching = '/coaching';
  static const notifications = '/notifications';
  static const notificationSettings = '/settings/notifications';
  static const communityPrivacy = '/community/privacy';
  static const reflection = '/coaching/reflection';
  static const deleteAccount = '/settings/privacy/delete';
  static const clinical = '/clinical';
  static const addVital = '/clinical/vitals/new';
  static const addLab = '/clinical/labs/new';
  static const report = '/settings/report';
  static const devices = '/settings/devices';
  static const quick = '/quick';
  static const summaryReport = '/settings/summary-report';
  static const appLock = '/settings/app-lock';
  static const learn = '/learn';
  static const cgm = '/settings/cgm';
  static const companions = '/settings/companions';
  static const guest = '/try';

  static const publicRoutes = {
    welcome,
    register,
    login,
    verifyEmail,
    forgotPassword,
    guest,
  };

  static const onboardingSequence = [
    onboardingIntro,
    onboardingConsent,
    onboardingProfile,
    onboardingHealth,
    onboardingPreferences,
    onboardingComplete,
  ];
}
