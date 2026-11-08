import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../../consent/application/consent_controller.dart';
import '../../preferences/application/preferences_controller.dart';
import '../data/activity_models.dart';
import '../data/activity_repository.dart';

final activityRepositoryProvider = Provider<ActivityRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  final id = auth is AuthAuthenticated ? auth.user.id : null;
  return ActivityRepository(
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
final activityProvider = FutureProvider.autoDispose
    .family<ActivityRecord, String>((ref, id) async {
      final repo = ref.watch(activityRepositoryProvider);
      await Future.wait([
        ref.watch(consentControllerProvider.future),
        ref.watch(preferencesControllerProvider.future),
      ]);
      return repo.get(id);
    });
typedef ActivityQuery = ({String? cursor, String? date, bool archived});
final activityPageProvider = FutureProvider.autoDispose
    .family<ActivityPage, ActivityQuery>((ref, query) async {
      final repo = ref.watch(activityRepositoryProvider);
      await Future.wait([
        ref.watch(consentControllerProvider.future),
        ref.watch(preferencesControllerProvider.future),
      ]);
      return repo.list(
        cursor: query.cursor,
        date: query.date,
        archived: query.archived,
      );
    });
final activityDayProvider = FutureProvider.autoDispose
    .family<ActivitySummary, String?>((ref, date) async {
      final repo = ref.watch(activityRepositoryProvider);
      await Future.wait([
        ref.watch(consentControllerProvider.future),
        ref.watch(preferencesControllerProvider.future),
      ]);
      return repo.summary(date: date);
    });
final activityRevisionsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, id) async {
      final repo = ref.watch(activityRepositoryProvider);
      await ref.watch(activityProvider(id).future);
      return repo.revisions(id);
    });

final activityWeekProvider = FutureProvider.autoDispose
    .family<ActivitySummary, String?>((ref, date) async {
      final repo = ref.watch(activityRepositoryProvider);
      await Future.wait([
        ref.watch(consentControllerProvider.future),
        ref.watch(preferencesControllerProvider.future),
      ]);
      return repo.summary(date: date, weekly: true);
    });
