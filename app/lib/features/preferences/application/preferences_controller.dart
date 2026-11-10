import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../data/preferences_models.dart';
import '../data/preferences_repository.dart';

final preferencesRepositoryProvider = Provider<PreferencesRepository>(
  (ref) => PreferencesRepository(ref.watch(apiClientProvider)),
);

final preferencesControllerProvider =
    AsyncNotifierProvider<PreferencesController, Preferences>(
      PreferencesController.new,
    );

final effectivePreferencesProvider = Provider<Preferences>((ref) {
  return ref.watch(preferencesControllerProvider).value ?? Preferences.defaults;
});

class PreferencesController extends AsyncNotifier<Preferences> {
  @override
  Future<Preferences> build() async {
    if (ref.watch(authControllerProvider) is! AuthAuthenticated) {
      return Preferences.defaults;
    }
    return ref.read(preferencesRepositoryProvider).get();
  }

  Future<void> save({
    String? timezone,
    GlucoseUnit? glucoseUnit,
    TextSizePreference? textSize,
    bool? reduceMotion,
  }) async {
    final preferences = await ref
        .read(preferencesRepositoryProvider)
        .update(
          timezone: timezone,
          glucoseUnit: glucoseUnit,
          textSize: textSize,
          reduceMotion: reduceMotion,
        );
    state = AsyncData(preferences);
    await ref.read(onboardingControllerProvider.notifier).refresh();
  }
}
