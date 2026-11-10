import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/offline/sync_controller.dart';
import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../../consent/application/consent_controller.dart';
import '../../preferences/application/preferences_controller.dart';
import '../data/goals_repository.dart';

final goalsRepositoryProvider = Provider<GoalsRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  final id = auth is AuthAuthenticated ? auth.user.id : null;
  return GoalsRepository(
    ref.watch(apiClientProvider),
    enqueueOffline: ref.read(syncControllerProvider.notifier).enqueue,
    isCurrentAccount: () {
      if (!ref.mounted) return false;
      final current = ref.read(authControllerProvider);
      return id != null &&
          current is AuthAuthenticated &&
          current.user.id == id;
    },
  );
});

final goalsListProvider = FutureProvider.autoDispose<List<Goal>>((ref) async {
  await Future.wait([
    ref.watch(consentControllerProvider.future),
    ref.watch(preferencesControllerProvider.future),
  ]);
  return ref.watch(goalsRepositoryProvider).list();
});
