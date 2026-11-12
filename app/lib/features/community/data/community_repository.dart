import '../../../core/network/account_scoped_repository.dart';

class Region {
  Region.fromJson(Map<String, dynamic> j)
    : code = j['code'] as String,
      name = j['name'] as String;
  final String code, name;
}

class ChallengeResult {
  ChallengeResult.fromJson(Map<String, dynamic> j)
    : completionStatus = j['completionStatus'] as String,
      label = j['label'] as String,
      finalScore = (j['finalScore'] as num?)?.toDouble(),
      finalActiveDays = j['finalActiveDays'] as int?;
  final String completionStatus, label;
  final double? finalScore;
  final int? finalActiveDays;
  bool get completed => completionStatus == 'COMPLETED';
}

class ChallengeSummary {
  ChallengeSummary.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      title = j['title'] as String,
      description = (j['description'] as String?) ?? '',
      startsOn = j['startsOn'] as String,
      endsOn = j['endsOn'] as String,
      targetDays = (j['targetDays'] as int?) ?? 0,
      status = (j['status'] as String?) ?? 'OPEN',
      statusLabel = (j['statusLabel'] as String?) ?? '',
      daysLeft = j['daysLeft'] as int?,
      participating = j['participating'] == true,
      leaderboardVisible = j['leaderboardVisible'] == true,
      participantsLabel = j['participantsLabel'] as String?,
      communityName = j['communityName'] as String?,
      activeDays = ((j['progress'] as Map?)?['activeDays'] as int?),
      score = ((j['progress'] as Map?)?['score'] as num?)?.toDouble(),
      myResult = j['myResult'] is Map
          ? ChallengeResult.fromJson(j['myResult'] as Map<String, dynamic>)
          : null;
  final String id, title, description, startsOn, endsOn, status, statusLabel;
  final int targetDays;
  final int? daysLeft, activeDays;
  final double? score;
  final bool participating, leaderboardVisible;
  final String? participantsLabel, communityName;
  final ChallengeResult? myResult;
  bool get open => status == 'OPEN';
  bool get scheduled => status == 'SCHEDULED';
  bool get closed => status == 'CLOSED';
}

class ChallengeDetail extends ChallengeSummary {
  ChallengeDetail.fromJson(super.j)
    : communityId = (j['community'] as Map)['id'] as String,
      communityName2 = (j['community'] as Map)['name'] as String,
      region = (j['community'] as Map)['region'] as String,
      alias = j['alias'] as String,
      rules = [for (final r in j['rules'] as List? ?? const []) r as String],
      activityDays = ((j['progress'] as Map?)?['activityDays'] as int?),
      checkinDays = ((j['progress'] as Map?)?['checkinDays'] as int?),
      canJoin = j['canJoin'] == true,
      canCheckin = j['canCheckin'] == true,
      checkedInToday = j['checkedInToday'] == true,
      super.fromJson();
  final String communityId, communityName2, region, alias;
  final List<String> rules;
  final int? activityDays, checkinDays;
  final bool canJoin, canCheckin, checkedInToday;
}

class Community {
  Community.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      description = j['description'] as String,
      memberCountLabel = j['memberCountLabel'] as String,
      myStatus = j['myStatus'] as String,
      challenges = [
        for (final c in j['challenges'] as List? ?? const [])
          ChallengeSummary.fromJson(c as Map<String, dynamic>),
      ];
  final String id, name, description, memberCountLabel, myStatus;
  final List<ChallengeSummary> challenges;
  bool get joined => myStatus == 'ACTIVE';
}

class MyMembership {
  MyMembership.fromJson(Map<String, dynamic> j)
    : communityId = j['communityId'] as String,
      name = j['name'] as String,
      region = j['region'] as String,
      alias = j['alias'] as String,
      aliasHidden = j['aliasHidden'] == true,
      openChallenges = (j['openChallenges'] as int?) ?? 0;
  final String communityId, name, region, alias;
  final bool aliasHidden;
  final int openChallenges;
}

class Recognition {
  Recognition.fromJson(Map<String, dynamic> j)
    : key = j['key'] as String,
      category = j['category'] as String,
      title = j['title'] as String,
      detail = j['detail'] as String,
      achievedAt = j['achievedAt'] as String?;
  final String key, category, title, detail;
  final String? achievedAt;
  bool get achieved => achievedAt != null;
}

class Highlight {
  Highlight.fromJson(Map<String, dynamic> j)
    : type = j['type'] as String,
      challengeId = j['challengeId'] as String?,
      title = j['title'] as String,
      detail = j['detail'] as String,
      ratio = (j['ratio'] as num?)?.toDouble(),
      statusLabel = j['statusLabel'] as String?;
  final String type, title, detail;
  final String? challengeId, statusLabel;
  final double? ratio;
}

class CommunityOverview {
  CommunityOverview.fromJson(Map<String, dynamic> j)
    : consentRequired = j['consentRequired'] == true,
      memberships = [
        for (final m in j['memberships'] as List? ?? const [])
          MyMembership.fromJson(m as Map<String, dynamic>),
      ],
      challenges = [
        for (final c in j['challenges'] as List? ?? const [])
          ChallengeSummary.fromJson(c as Map<String, dynamic>),
      ],
      recognitions = [
        for (final r in j['recognitions'] as List? ?? const [])
          Recognition.fromJson(r as Map<String, dynamic>),
      ],
      upcomingRecognitions = [
        for (final r in j['upcomingRecognitions'] as List? ?? const [])
          Recognition.fromJson(r as Map<String, dynamic>),
      ],
      highlight = j['highlight'] is Map
          ? Highlight.fromJson(j['highlight'] as Map<String, dynamic>)
          : null,
      highlightsEnabled = j['highlightsEnabled'] != false;
  final bool consentRequired, highlightsEnabled;
  final List<MyMembership> memberships;
  final List<ChallengeSummary> challenges;
  final List<Recognition> recognitions, upcomingRecognitions;
  final Highlight? highlight;
}

class CommunityPrivacy {
  CommunityPrivacy.fromJson(Map<String, dynamic> j)
    : memberships = [
        for (final m in j['memberships'] as List? ?? const [])
          (
            communityId: (m as Map)['communityId'] as String,
            name: m['name'] as String,
            alias: m['alias'] as String,
          ),
      ],
      visibleOn = [
        for (final v in j['visibleOn'] as List? ?? const [])
          (
            challengeId: (v as Map)['challengeId'] as String,
            title: v['title'] as String,
          ),
      ],
      highlightsEnabled = j['highlightsEnabled'] != false,
      shared = [for (final s in j['shared'] as List? ?? const []) s as String],
      neverShared = [
        for (final s in j['neverShared'] as List? ?? const []) s as String,
      ];
  final List<({String communityId, String name, String alias})> memberships;
  final List<({String challengeId, String title})> visibleOn;
  final bool highlightsEnabled;
  final List<String> shared, neverShared;
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
      minimumCohort = (j['minimumCohort'] as int?) ?? 5,
      items = [
        for (final v in (j['items'] as List? ?? const []))
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
  Future<void> setAlias(String communityId, String alias) async => write(
    'PATCH',
    '/api/me/communities/$communityId/alias',
    {'alias': alias},
  );
  Future<void> leave(String communityId) async =>
      write('POST', '/api/me/communities/$communityId/leave', {});
  Future<List<ChallengeSummary>> challenges(String communityId) async => [
    for (final v
        in (await api.get(
              '/api/me/communities/$communityId/challenges',
            )).object['items']
            as List)
      ChallengeSummary.fromJson(v as Map<String, dynamic>),
  ];
  Future<ChallengeDetail> challenge(String id) async =>
      ChallengeDetail.fromJson(
        (await api.get('/api/me/challenges/$id')).object,
      );
  Future<List<ChallengeSummary>> history() async => [
    for (final v
        in (await api.get('/api/me/challenges/history')).object['items']
            as List)
      ChallengeSummary.fromJson(v as Map<String, dynamic>),
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
  Future<String> reportAlias(
    String challengeId,
    String alias,
    String reason,
  ) async =>
      ((await write('POST', '/api/me/challenges/$challengeId/reports', {
            'alias': alias,
            'reason': reason,
          })).object['message']
          as String?) ??
      'Terima kasih. Laporan akan ditinjau.';
  Future<Leaderboard> leaderboard(String id) async => Leaderboard.fromJson(
    (await api.get('/api/me/challenges/$id/leaderboard?limit=20')).object,
  );
  Future<CommunityOverview> overview() async => CommunityOverview.fromJson(
    (await api.get('/api/me/community/overview')).object,
  );
  Future<CommunityPrivacy> privacy() async => CommunityPrivacy.fromJson(
    (await api.get('/api/me/community/privacy')).object,
  );
  Future<CommunityPrivacy> hideFromLeaderboards() async =>
      CommunityPrivacy.fromJson(
        (await write(
          'POST',
          '/api/me/community/privacy/hide-leaderboards',
          {},
        )).object,
      );
  Future<CommunityPrivacy> setHighlights(bool enabled) async =>
      CommunityPrivacy.fromJson(
        (await write('PATCH', '/api/me/community/privacy', {
          'highlightsEnabled': enabled,
        })).object,
      );
}
