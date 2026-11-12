import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../../consent/application/consent_controller.dart';
import '../data/quick_record_repository.dart';

final quickRecordRepositoryProvider = Provider<QuickRecordRepository>(
  (ref) => QuickRecordRepository(ref.watch(apiClientProvider)),
);

final quickSuggestionsProvider = FutureProvider.autoDispose<QuickSuggestions?>((
  ref,
) async {
  if (ref.watch(authControllerProvider) is! AuthAuthenticated) return null;
  await ref.watch(consentControllerProvider.future);
  try {
    return await ref.watch(quickRecordRepositoryProvider).suggestions();
  } catch (_) {
    return null;
  }
});
