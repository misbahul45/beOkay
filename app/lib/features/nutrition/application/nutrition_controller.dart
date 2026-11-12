import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/offline/sync_controller.dart';
import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../../consent/application/consent_controller.dart';
import '../../preferences/application/preferences_controller.dart';
import '../data/nutrition_models.dart';
import '../data/nutrition_repository.dart';

final nutritionRepositoryProvider = Provider<NutritionRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  final id = auth is AuthAuthenticated ? auth.user.id : null;
  return NutritionRepository(
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
final mealProvider = FutureProvider.autoDispose.family<MealRecord, String>((
  ref,
  id,
) async {
  final repo = ref.watch(nutritionRepositoryProvider);
  final consent = ref.watch(consentControllerProvider.future);
  final prefs = ref.watch(preferencesControllerProvider.future);
  await Future.wait([consent, prefs]);
  return repo.get(id);
});
typedef MealQuery = ({String? cursor, String? date, bool archived});
final mealPageProvider = FutureProvider.autoDispose.family<MealPage, MealQuery>(
  (ref, query) async {
    final repo = ref.watch(nutritionRepositoryProvider);
    final consent = ref.watch(consentControllerProvider.future),
        prefs = ref.watch(preferencesControllerProvider.future);
    await Future.wait([consent, prefs]);
    return repo.list(
      cursor: query.cursor,
      date: query.date,
      archived: query.archived,
    );
  },
);
final mealRevisionsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, id) async {
      final repo = ref.watch(nutritionRepositoryProvider);
      await ref.watch(mealProvider(id).future);
      return repo.revisions(id);
    });

final mealContextProvider = FutureProvider.autoDispose
    .family<MealContext?, String>((ref, id) async {
      final repo = ref.watch(nutritionRepositoryProvider);
      await ref.watch(mealProvider(id).future);
      try {
        return await repo.context(id);
      } catch (_) {
        return null;
      }
    });
