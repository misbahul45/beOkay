import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../data/health_models.dart';
import '../data/health_repository.dart';

final healthRepositoryProvider = Provider<HealthRepository>(
  (ref) => HealthRepository(ref.watch(apiClientProvider)),
);

final healthControllerProvider =
    AsyncNotifierProvider<HealthController, HealthProfile?>(
      HealthController.new,
    );

class HealthController extends AsyncNotifier<HealthProfile?> {
  @override
  Future<HealthProfile?> build() async {
    if (ref.watch(authControllerProvider) is! AuthAuthenticated) return null;
    return ref.read(healthRepositoryProvider).get();
  }

  Future<void> save({
    required DiagnosisStatus status,
    required DiabetesType? type,
    required int? year,
    required List<Treatment> treatments,
    RiskStatement? risk,
  }) async {
    final profile = await ref
        .read(healthRepositoryProvider)
        .save(
          status: status,
          type: type,
          year: year,
          treatments: treatments,
          risk: risk,
        );
    state = AsyncData(profile);
    await ref.read(onboardingControllerProvider.notifier).refresh();
  }
}
