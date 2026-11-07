import 'package:app/core/router/redirect.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/auth/data/session_user.dart';
import 'package:app/features/onboarding/data/onboarding_status.dart';
import 'package:flutter_test/flutter_test.dart';

OnboardingStatus status(OnboardingState state, {bool review = false}) => OnboardingStatus(
      state: state,
      emailVerified: true,
      steps: const {},
      version: 0,
      requiresConsentReview: review,
    );

final signedIn = AuthAuthenticated(const SessionUser(id: '1', email: 'a@b.c', name: 'A', emailVerified: true));

String? redirect(AuthState auth, String location, {OnboardingLoad load = OnboardingLoad.ready, OnboardingStatus? onboarding}) =>
    computeRedirect(auth: auth, onboardingLoad: load, onboarding: onboarding, location: location);

void main() {
  group('unauthenticated', () {
    const out = AuthUnauthenticated();
    test('public routes stay', () {
      for (final route in Routes.publicRoutes) {
        expect(redirect(out, route), isNull, reason: route);
      }
    });
    test('private routes go to welcome', () {
      for (final route in [Routes.home, Routes.profile, Routes.settings, Routes.onboardingConsent, Routes.splash]) {
        expect(redirect(out, route), Routes.welcome, reason: route);
      }
    });
    test('query strings do not defeat public matching', () {
      expect(redirect(out, '${Routes.verifyEmail}?email=a%40b.c'), isNull);
    });
  });

  group('auth not resolved', () {
    test('loading and unavailable hold on splash', () {
      expect(redirect(const AuthLoading(), Routes.home), Routes.splash);
      expect(redirect(const AuthUnavailable('x'), Routes.login), Routes.splash);
      expect(redirect(const AuthLoading(), Routes.splash), isNull);
    });
  });

  group('authenticated onboarding', () {
    test('waits on splash until onboarding is loaded', () {
      expect(redirect(signedIn, Routes.login, load: OnboardingLoad.loading), Routes.splash);
      expect(redirect(signedIn, Routes.splash, load: OnboardingLoad.error), isNull);
    });
    test('each state maps to its first incomplete step', () {
      final expected = {
        OnboardingState.notStarted: Routes.onboardingIntro,
        OnboardingState.consentPending: Routes.onboardingConsent,
        OnboardingState.personalProfilePending: Routes.onboardingProfile,
        OnboardingState.healthProfilePending: Routes.onboardingHealth,
        OnboardingState.preferencesPending: Routes.onboardingPreferences,
        OnboardingState.readyToComplete: Routes.onboardingComplete,
      };
      expected.forEach((state, route) {
        expect(redirect(signedIn, Routes.splash, onboarding: status(state)), route, reason: state.name);
        expect(redirect(signedIn, route, onboarding: status(state)), isNull, reason: 'stable at $route');
      });
    });
    test('may revisit earlier steps but not skip ahead', () {
      final current = status(OnboardingState.healthProfilePending);
      expect(redirect(signedIn, Routes.onboardingConsent, onboarding: current), isNull);
      expect(redirect(signedIn, Routes.onboardingProfile, onboarding: current), isNull);
      expect(redirect(signedIn, Routes.onboardingPreferences, onboarding: current), Routes.onboardingHealth);
      expect(redirect(signedIn, Routes.home, onboarding: current), Routes.onboardingHealth);
    });
    test('login and register bounce into onboarding', () {
      expect(redirect(signedIn, Routes.login, onboarding: status(OnboardingState.consentPending)), Routes.onboardingConsent);
    });
  });

  group('completed', () {
    final done = status(OnboardingState.completed);
    test('leaves splash, public and onboarding routes for home', () {
      for (final route in [Routes.splash, Routes.welcome, Routes.login, Routes.onboardingConsent, Routes.onboardingComplete]) {
        expect(redirect(signedIn, route, onboarding: done), Routes.home, reason: route);
      }
    });
    test('app routes are untouched, including after consent withdrawal', () {
      for (final route in [Routes.home, Routes.profile, Routes.editHealth, Routes.settings, Routes.consentManagement, Routes.accountSecurity]) {
        expect(redirect(signedIn, route, onboarding: done), isNull, reason: route);
        expect(redirect(signedIn, route, onboarding: status(OnboardingState.completed, review: true)), isNull, reason: route);
      }
    });
  });

  test('no redirect loops: applying the result again is stable', () {
    final states = [
      (const AuthUnauthenticated(), OnboardingLoad.ready, null),
      (signedIn, OnboardingLoad.ready, status(OnboardingState.consentPending)),
      (signedIn, OnboardingLoad.ready, status(OnboardingState.completed)),
      (signedIn, OnboardingLoad.loading, null),
    ];
    for (final (auth, load, onboarding) in states) {
      for (final start in [Routes.splash, Routes.welcome, Routes.home, Routes.onboardingHealth, Routes.settings]) {
        final first = redirect(auth, start, load: load, onboarding: onboarding);
        if (first != null) {
          expect(redirect(auth, first, load: load, onboarding: onboarding), isNull, reason: '$start -> $first');
        }
      }
    }
  });
}
