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
    .family<List<ChallengeSummary>, String>(
      (ref, communityId) =>
          ref.watch(communityRepositoryProvider).challenges(communityId),
    );
final challengeDetailProvider = FutureProvider.autoDispose
    .family<ChallengeDetail, String>(
      (ref, id) => ref.watch(communityRepositoryProvider).challenge(id),
    );
final leaderboardProvider = FutureProvider.autoDispose
    .family<Leaderboard, String>(
      (ref, id) => ref.watch(communityRepositoryProvider).leaderboard(id),
    );
final challengeHistoryProvider =
    FutureProvider.autoDispose<List<ChallengeSummary>>(
      (ref) => ref.watch(communityRepositoryProvider).history(),
    );
final communityOverviewProvider = FutureProvider.autoDispose<CommunityOverview>(
  (ref) => ref.watch(communityRepositoryProvider).overview(),
);
final communityPrivacyProvider = FutureProvider.autoDispose<CommunityPrivacy>(
  (ref) => ref.watch(communityRepositoryProvider).privacy(),
);
final homeHighlightProvider = FutureProvider.autoDispose<Highlight?>((
  ref,
) async {
  try {
    return (await ref.watch(communityRepositoryProvider).overview()).highlight;
  } catch (_) {
    return null;
  }
});
