import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/journey_repository.dart';

final journeyRepositoryProvider = Provider<JourneyRepository>(
  (ref) => JourneyRepository(ref.watch(apiClientProvider)),
);

final journeyProvider = FutureProvider.autoDispose<JourneyView>(
  (ref) => ref.watch(journeyRepositoryProvider).get(),
);
