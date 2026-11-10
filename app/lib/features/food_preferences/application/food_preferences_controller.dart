import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../../consent/application/consent_controller.dart';
import '../data/food_preferences_repository.dart';

final foodPreferencesRepositoryProvider = Provider<FoodPreferencesRepository>((
  ref,
) {
  final auth = ref.watch(authControllerProvider);
  final id = auth is AuthAuthenticated ? auth.user.id : null;
  return FoodPreferencesRepository(
    ref.watch(apiClientProvider),
    isCurrentAccount: () {
      if (!ref.mounted) return false;
      final current = ref.read(authControllerProvider);
      return id != null &&
          current is AuthAuthenticated &&
          current.user.id == id;
    },
  );
});

final foodPreferencesProvider =
    FutureProvider.autoDispose<List<FoodPreference>>((ref) async {
      await ref.watch(consentControllerProvider.future);
      return ref.watch(foodPreferencesRepositoryProvider).list();
    });
