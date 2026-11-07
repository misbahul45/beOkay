import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../../health_profile/application/health_controller.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../data/consent_models.dart';
import '../data/consent_repository.dart';

final consentRepositoryProvider = Provider<ConsentRepository>((ref) => ConsentRepository(ref.watch(apiClientProvider)));

final consentPolicyProvider = FutureProvider<ConsentPolicy>((ref) => ref.watch(consentRepositoryProvider).currentPolicy());

final consentControllerProvider = AsyncNotifierProvider<ConsentController, ConsentOverview?>(ConsentController.new);

class ConsentController extends AsyncNotifier<ConsentOverview?> {
  @override
  Future<ConsentOverview?> build() async {
    if (ref.watch(authControllerProvider) is! AuthAuthenticated) return null;
    return ref.read(consentRepositoryProvider).overview();
  }

  ConsentRepository get _repo => ref.read(consentRepositoryProvider);

  Future<void> grant({required String policyVersion, required List<String> purposes, required String source}) async {
    final overview = await _repo.grant(policyVersion: policyVersion, purposes: purposes, source: source);
    ref.invalidate(healthControllerProvider);
    state = AsyncData(overview);
    await ref.read(onboardingControllerProvider.notifier).refresh();
  }

  Future<void> withdraw(List<String> purposes) async {
    final overview = await _repo.withdraw(purposes);
    ref.invalidate(healthControllerProvider);
    state = AsyncData(overview);
    await ref.read(onboardingControllerProvider.notifier).refresh();
  }
}
