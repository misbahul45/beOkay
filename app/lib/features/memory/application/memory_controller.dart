import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../data/memory_repository.dart';

final memoryRepositoryProvider = Provider<MemoryRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  final id = auth is AuthAuthenticated ? auth.user.id : null;
  return MemoryRepository(
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

final memoryOverviewProvider = FutureProvider.autoDispose<MemoryOverview>(
  (ref) => ref.watch(memoryRepositoryProvider).overview(),
);

final personalizationSummaryProvider =
    FutureProvider.autoDispose<PersonalizationSummary?>((ref) async {
      try {
        return await ref.watch(memoryRepositoryProvider).personalization();
      } catch (_) {
        return null;
      }
    });

final memoryHistoryProvider = FutureProvider.autoDispose
    .family<List<MemoryRevisionEntry>, String>(
      (ref, id) => ref.watch(memoryRepositoryProvider).history(id),
    );
