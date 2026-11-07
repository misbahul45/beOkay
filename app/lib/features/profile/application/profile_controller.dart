import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../data/profile_models.dart';
import '../data/profile_repository.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => ProfileRepository(ref.watch(apiClientProvider)));

final profileControllerProvider = AsyncNotifierProvider<ProfileController, Profile?>(ProfileController.new);

class ProfileController extends AsyncNotifier<Profile?> {
  @override
  Future<Profile?> build() async {
    if (ref.watch(authControllerProvider) is! AuthAuthenticated) return null;
    return ref.read(profileRepositoryProvider).get();
  }

  Future<void> save({String? displayName, int? birthYear, bool clearBirthYear = false}) async {
    final profile = await ref.read(profileRepositoryProvider).update(
          displayName: displayName,
          birthYear: birthYear,
          clearBirthYear: clearBirthYear,
        );
    state = AsyncData(profile);
    if (displayName != null) ref.read(authControllerProvider.notifier).updateDisplayName(profile.displayName);
    await ref.read(onboardingControllerProvider.notifier).refresh();
  }
}
