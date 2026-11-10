import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../data/onboarding_repository.dart';
import '../data/onboarding_status.dart';

final onboardingRepositoryProvider = Provider<OnboardingRepository>(
  (ref) => OnboardingRepository(ref.watch(apiClientProvider)),
);

final onboardingControllerProvider =
    AsyncNotifierProvider<OnboardingController, OnboardingStatus?>(
      OnboardingController.new,
    );

class OnboardingController extends AsyncNotifier<OnboardingStatus?> {
  @override
  Future<OnboardingStatus?> build() async {
    final auth = ref.watch(authControllerProvider);
    if (auth is! AuthAuthenticated) return null;
    return ref.read(onboardingRepositoryProvider).get();
  }

  OnboardingRepository get _repo => ref.read(onboardingRepositoryProvider);

  Future<void> refresh() async {
    final status = await _repo.get();
    state = AsyncData(status);
  }

  Future<void> markIntroSeen() async {
    final current = state.value;
    final status = await _repo.markIntroSeen(current?.version ?? 0);
    state = AsyncData(status);
  }

  Future<void> complete() async {
    final status = await _repo.complete();
    state = AsyncData(status);
  }
}
