import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/offline/sync_controller.dart';
import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../../consent/application/consent_controller.dart';
import '../../preferences/application/preferences_controller.dart';
import '../data/glucose_models.dart';
import '../data/glucose_repository.dart';

final glucoseRepositoryProvider = Provider<GlucoseRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  final id = auth is AuthAuthenticated ? auth.user.id : null;
  return GlucoseRepository(
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
final glucoseProvider = FutureProvider.autoDispose
    .family<GlucoseRecord, String>((ref, id) async {
      final repo = ref.watch(glucoseRepositoryProvider);
      await Future.wait([
        ref.watch(consentControllerProvider.future),
        ref.watch(preferencesControllerProvider.future),
      ]);
      return repo.get(id);
    });
typedef GlucoseQuery = ({String? cursor, String? date, bool archived});
final glucosePageProvider = FutureProvider.autoDispose
    .family<GlucosePage, GlucoseQuery>((ref, query) async {
      final repo = ref.watch(glucoseRepositoryProvider);
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
final glucoseDayProvider = FutureProvider.autoDispose
    .family<GlucoseDay, String?>((ref, date) async {
      final repo = ref.watch(glucoseRepositoryProvider);
      await Future.wait([
        ref.watch(consentControllerProvider.future),
        ref.watch(preferencesControllerProvider.future),
      ]);
      return repo.daily(date: date);
    });
final glucoseRevisionsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, id) async {
      final repo = ref.watch(glucoseRepositoryProvider);
      await ref.watch(glucoseProvider(id).future);
      return repo.revisions(id);
    });
