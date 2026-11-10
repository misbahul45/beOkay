enum OnboardingState {
  emailVerificationPending('EMAIL_VERIFICATION_PENDING'),
  notStarted('NOT_STARTED'),
  consentPending('CONSENT_PENDING'),
  personalProfilePending('PERSONAL_PROFILE_PENDING'),
  healthProfilePending('HEALTH_PROFILE_PENDING'),
  preferencesPending('PREFERENCES_PENDING'),
  readyToComplete('READY_TO_COMPLETE'),
  completed('COMPLETED');

  const OnboardingState(this.wire);
  final String wire;

  static OnboardingState parse(String value) =>
      OnboardingState.values.firstWhere(
        (state) => state.wire == value,
        orElse: () => OnboardingState.notStarted,
      );
}

class OnboardingStatus {
  const OnboardingStatus({
    required this.state,
    required this.emailVerified,
    required this.steps,
    required this.version,
    required this.requiresConsentReview,
  });

  final OnboardingState state;
  final bool emailVerified;
  final Map<String, bool> steps;
  final int version;
  final bool requiresConsentReview;

  bool get isCompleted => state == OnboardingState.completed;

  int get completedSteps => steps.values.where((done) => done).length;

  factory OnboardingStatus.fromJson(Map<String, dynamic> json) {
    final steps = <String, bool>{};
    for (final step in (json['steps'] as List<dynamic>? ?? const [])) {
      final map = step as Map<String, dynamic>;
      steps[map['key'] as String] = map['done'] as bool;
    }
    return OnboardingStatus(
      state: OnboardingState.parse(json['state'] as String),
      emailVerified: json['emailVerified'] as bool? ?? false,
      steps: steps,
      version: json['version'] as int? ?? 0,
      requiresConsentReview: json['requiresConsentReview'] as bool? ?? false,
    );
  }
}
