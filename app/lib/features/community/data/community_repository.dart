import '../../../core/network/account_scoped_repository.dart';

class Region {
  Region.fromJson(Map<String, dynamic> j)
    : code = j['code'] as String,
      name = j['name'] as String;
  final String code, name;
}

class Community {
  Community.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      description = j['description'] as String,
      memberCountLabel = j['memberCountLabel'] as String,
      myStatus = j['myStatus'] as String;
  final String id, name, description, memberCountLabel, myStatus;
  bool get joined => myStatus == 'ACTIVE';
}

class MyMembership {
  MyMembership.fromJson(Map<String, dynamic> j)
    : communityId = j['communityId'] as String,
      name = j['name'] as String,
      region = j['region'] as String,
      alias = j['alias'] as String;
  final String communityId, name, region, alias;
}

class Challenge {
  Challenge.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      title = j['title'] as String,
      description = j['description'] as String,
      startsOn = j['startsOn'] as String,
      endsOn = j['endsOn'] as String,
      targetDays = j['targetDays'] as int,
      participating = j['participating'] == true,
      leaderboardVisible = j['leaderboardVisible'] == true;
  final String id, title, description, startsOn, endsOn;
  final int targetDays;
  final bool participating, leaderboardVisible;
}

class ChallengeProgress {
  ChallengeProgress.fromJson(Map<String, dynamic> j)
    : score = (j['score'] as num).toDouble(),
      activityDays = j['activityDays'] as int,
      checkinDays = j['checkinDays'] as int,
      targetDays = j['targetDays'] as int,
      leaderboardVisible = j['leaderboardVisible'] == true,
      note = j['note'] as String;
  final double score;
  final int activityDays, checkinDays, targetDays;
  final bool leaderboardVisible;
  final String note;
}

class LeaderboardRow {
  LeaderboardRow.fromJson(Map<String, dynamic> j)
    : rank = j['rank'] as int,
      alias = j['alias'] as String,
      score = (j['score'] as num).toDouble(),
      isMe = j['isMe'] == true;
  final int rank;
  final String alias;
  final double score;
  final bool isMe;
}

class Leaderboard {
  Leaderboard.fromJson(Map<String, dynamic> j)
    : suppressed = j['suppressed'] == true,
      reason = j['reason'] as String?,
      minimumCohort = j['minimumCohort'] as int,
      items = [
        for (final v in (j['items'] as List))
          LeaderboardRow.fromJson(v as Map<String, dynamic>),
      ],
      myScore = ((j['me'] as Map<String, dynamic>?)?['score'] as num?)
          ?.toDouble();
  final bool suppressed;
  final String? reason;
  final int minimumCohort;
  final List<LeaderboardRow> items;
  final double? myScore;
}

class CommunityRepository extends AccountScopedRepository {
  CommunityRepository(super.api, {required super.isCurrentAccount});

  Future<List<Region>> regions() async => [
    for (final v in (await api.get('/api/regions')).object['items'] as List)
      Region.fromJson(v as Map<String, dynamic>),
  ];
  Future<List<Community>> communities(String regionCode) async => [
    for (final v
        in (await api.get(
              '/api/me/communities?regionCode=$regionCode',
            )).object['items']
            as List)
      Community.fromJson(v as Map<String, dynamic>),
  ];
  Future<List<MyMembership>> mine() async => [
    for (final v
        in (await api.get('/api/me/communities/mine')).object['items'] as List)
      MyMembership.fromJson(v as Map<String, dynamic>),
  ];
  Future<void> join(String communityId, String alias) async =>
      write('POST', '/api/me/communities/$communityId/join', {'alias': alias});
  Future<void> leave(String communityId) async =>
      write('POST', '/api/me/communities/$communityId/leave', {});
  Future<List<Challenge>> challenges(String communityId) async => [
    for (final v
        in (await api.get(
              '/api/me/communities/$communityId/challenges',
            )).object['items']
            as List)
      Challenge.fromJson(v as Map<String, dynamic>),
  ];
  Future<void> joinChallenge(String id, {required bool visible}) async => write(
    'POST',
    '/api/me/challenges/$id/join',
    {'leaderboardVisible': visible},
  );
  Future<void> leaveChallenge(String id) async =>
      write('POST', '/api/me/challenges/$id/leave', {});
  Future<void> setVisibility(String id, bool visible) async =>
      write('PATCH', '/api/me/challenges/$id/visibility', {'visible': visible});
  Future<void> checkin(String id) async =>
      write('POST', '/api/me/challenges/$id/checkins', {});
  Future<ChallengeProgress> progress(String id) async =>
      ChallengeProgress.fromJson(
        (await api.get('/api/me/challenges/$id/progress')).object,
      );
  Future<Leaderboard> leaderboard(String id) async => Leaderboard.fromJson(
    (await api.get('/api/me/challenges/$id/leaderboard?limit=20')).object,
  );
}
