import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../data/coaching_repository.dart';

final coachingRepositoryProvider = Provider<CoachingRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  final id = auth is AuthAuthenticated ? auth.user.id : null;
  return CoachingRepository(
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

final coachingOverviewProvider = FutureProvider.autoDispose<CoachingOverview>(
  (ref) => ref.watch(coachingRepositoryProvider).overview(),
);

final reflectionProvider = FutureProvider.autoDispose<Reflection>(
  (ref) => ref.watch(coachingRepositoryProvider).reflection(),
);
