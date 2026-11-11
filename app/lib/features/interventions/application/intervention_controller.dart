import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../data/intervention_repository.dart';

final interventionRepositoryProvider = Provider<InterventionRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  final id = auth is AuthAuthenticated ? auth.user.id : null;
  return InterventionRepository(
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

/// Saran yang berlaku sekarang. Kegagalan APA PUN berarti "tidak ada saran": kartu ini opsional dan tidak pernah menampilkan galat.
final openInterventionsProvider =
    FutureProvider.autoDispose<List<Intervention>>((ref) async {
      final repo = ref.watch(interventionRepositoryProvider);
      for (final trigger in const [
        'COACHING_ACTION_DUE',
        'WEEKLY_REVIEW_AVAILABLE',
        'GOAL_WINDOW_APPROACHING',
      ]) {
        try {
          await repo.consider(trigger);
        } catch (_) {}
      }
      try {
        return await repo.open();
      } catch (_) {
        return const [];
      }
    });
