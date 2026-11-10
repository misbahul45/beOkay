import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../data/coach_repository.dart';

final coachRepositoryProvider = Provider<CoachRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  final id = auth is AuthAuthenticated ? auth.user.id : null;
  return CoachRepository(
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

final plannedMealsProvider = FutureProvider.autoDispose<List<PlannedMeal>>(
  (ref) => ref.watch(coachRepositoryProvider).plannedMeals(),
);

final activityPlansProvider = FutureProvider.autoDispose<List<ActivityPlan>>(
  (ref) => ref.watch(coachRepositoryProvider).activityPlans(),
);
