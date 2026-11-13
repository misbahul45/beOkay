import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/next_action_repository.dart';

final nextActionRepositoryProvider = Provider<NextActionRepository>(
  (ref) => NextActionRepository(ref.watch(apiClientProvider)),
);

final nextActionProvider = FutureProvider.autoDispose<NextActionView?>((
  ref,
) async {
  try {
    return await ref.watch(nextActionRepositoryProvider).get();
  } catch (_) {
    return null;
  }
});
