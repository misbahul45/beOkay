import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/offline/sync_controller.dart';
import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../../consent/application/consent_controller.dart';
import '../../preferences/application/preferences_controller.dart';
import '../data/medication_repository.dart';

final medicationRepositoryProvider = Provider<MedicationRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  final id = auth is AuthAuthenticated ? auth.user.id : null;
  return MedicationRepository(
    ref.watch(apiClientProvider),
    enqueueOffline: ref.read(syncControllerProvider.notifier).enqueue,
    isCurrentAccount: () {
      if (!ref.mounted) return false;
      final current = ref.read(authControllerProvider);
      return id != null && current is AuthAuthenticated && current.user.id == id;
    },
  );
});

Future<void> _ready(Ref ref) => Future.wait([ref.watch(consentControllerProvider.future), ref.watch(preferencesControllerProvider.future)]);

final medicationListProvider = FutureProvider.autoDispose<List<Regimen>>((ref) async {
  await _ready(ref);
  return ref.watch(medicationRepositoryProvider).list();
});

final medicationTodayProvider = FutureProvider.autoDispose<MedicationToday>((ref) async {
  await _ready(ref);
  return ref.watch(medicationRepositoryProvider).today();
});

final medicationIntakesProvider = FutureProvider.autoDispose.family<List<IntakeRecord>, String>((ref, regimenId) async {
  await _ready(ref);
  return ref.watch(medicationRepositoryProvider).intakes(regimenId);
});
