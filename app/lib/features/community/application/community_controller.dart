import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../data/community_repository.dart';

final communityRepositoryProvider = Provider<CommunityRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  final id = auth is AuthAuthenticated ? auth.user.id : null;
  return CommunityRepository(
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

final regionsProvider = FutureProvider.autoDispose<List<Region>>(
  (ref) => ref.watch(communityRepositoryProvider).regions(),
);
final myCommunitiesProvider = FutureProvider.autoDispose<List<MyMembership>>(
  (ref) => ref.watch(communityRepositoryProvider).mine(),
);
final communitiesInRegionProvider = FutureProvider.autoDispose
    .family<List<Community>, String>(
      (ref, code) => ref.watch(communityRepositoryProvider).communities(code),
    );
final challengesProvider = FutureProvider.autoDispose
    .family<List<Challenge>, String>(
      (ref, communityId) =>
          ref.watch(communityRepositoryProvider).challenges(communityId),
    );
