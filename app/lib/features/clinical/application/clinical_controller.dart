import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/offline/sync_controller.dart';
import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../../consent/application/consent_controller.dart';
import '../data/clinical_models.dart';
import '../data/clinical_repository.dart';

final clinicalRepositoryProvider = Provider<ClinicalRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  final id = auth is AuthAuthenticated ? auth.user.id : null;
  return ClinicalRepository(
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

final clinicalSummaryProvider = FutureProvider.autoDispose<ClinicalSummary>((
  ref,
) async {
  await ref.watch(consentControllerProvider.future);
  return ref.watch(clinicalRepositoryProvider).summary();
});

final vitalHistoryProvider = FutureProvider.autoDispose
    .family<List<VitalRecord>, String>(
      (ref, kind) => ref.watch(clinicalRepositoryProvider).vitals(kind: kind),
    );

final labHistoryProvider = FutureProvider.autoDispose
    .family<List<LabRecord>, String>(
      (ref, test) => ref.watch(clinicalRepositoryProvider).labs(test: test),
    );
