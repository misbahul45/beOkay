import '../../education/education.dart';

class ConversationThread {
  ConversationThread.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      title = j['title'] as String?,
      messageCount = (j['messageCount'] as int?) ?? 0,
      lastMessageAt = j['lastMessageAt'] == null
          ? null
          : DateTime.parse(j['lastMessageAt'] as String).toLocal();
  final String id;
  final String? title;
  final int messageCount;
  final DateTime? lastMessageAt;
}

class Suggestion {
  const Suggestion(this.label, this.message);
  Suggestion.fromJson(Map<String, dynamic> j)
    : label = j['label'] as String,
      message = j['message'] as String;
  final String label, message;
}

class ChatRecommendation {
  ChatRecommendation.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      version = j['version'] as int,
      status = j['status'] as String,
      type = (j['type'] as String?) ?? 'NUTRITION',
      name = j['name'] as String,
      match = j['match'] as String?,
      provenance = (j['provenance'] as String?) ?? '',
      completeness = (j['completeness'] as String?) ?? 'NONE',
      per100g = ((j['per100g'] as Map<String, dynamic>?) ?? const {}).map(
        (k, v) => MapEntry(k, v as num?),
      ),
      activityType =
          (j['activity'] as Map<String, dynamic>?)?['type'] as String?,
      activityMinutes =
          (j['activity'] as Map<String, dynamic>?)?['durationMinutes'] as int?,
      explanation = (j['explanation'] as String?) ?? '',
      rankingReason = (j['rankingReason'] as String?) ?? '',
      limitations = [
        for (final l in (j['limitations'] as List? ?? const [])) l as String,
      ],
      writtenByModel = j['writtenByModel'] == true;

  final String id, status, type, name, provenance, completeness;
  final String explanation, rankingReason;
  final String? match, activityType;
  final int version;
  final int? activityMinutes;
  final Map<String, num?> per100g;
  final List<String> limitations;
  final bool writtenByModel;

  bool get isActivity => type == 'ACTIVITY';
  bool get offered => status == 'OFFERED';
  num? get calories => per100g['calories'];

  String get activityLabel => switch (activityType) {
    'walking' => 'Jalan kaki',
    'cycling' => 'Bersepeda',
    'running' => 'Lari',
    'strength' => 'Latihan kekuatan',
    'swimming' => 'Berenang',
    _ => name,
  };

  String get statusLabel => switch (status) {
    'ACCEPTED' => 'Masuk rencana',
    'REJECTED' => 'Dilewati',
    'EXPIRED' => 'Kedaluwarsa',
    _ => 'Tidak berlaku',
  };
}

sealed class ChatPart {
  const ChatPart();

  static ChatPart? fromJson(Map<String, dynamic> j) => switch (j['type']) {
    'text' => TextPart(j['text'] as String),
    'statistic' => StatisticPart.fromJson(j),
    'recommendations' => RecommendationsPart.fromJson(j),
    'no_match' => NoMatchPart(j['query'] as String, j['text'] as String),
    'safety' => SafetyPart(
      code: j['code'] as String,
      title: j['title'] as String,
      text: j['text'] as String,
      urgent: j['urgent'] == true,
    ),
    'notice' => NoticePart(j['tone'] as String, j['text'] as String),
    'consent_required' => ConsentPart(
      j['purpose'] as String,
      j['text'] as String,
    ),
    'suggestions' => SuggestionsPart([
      for (final s in j['items'] as List)
        Suggestion.fromJson(s as Map<String, dynamic>),
    ]),
    'link' => LinkPart(j['label'] as String, j['target'] as String),
    'meal_draft' => MealDraftPart(
      j['draftId'] as String,
      j['draft'] == null
          ? null
          : MealDraft.fromJson(j['draft'] as Map<String, dynamic>),
    ),
    'memory_proposal' => MemoryProposalPart(
      j['memoryId'] as String,
      j['memory'] == null
          ? null
          : MemoryProposal.fromJson(j['memory'] as Map<String, dynamic>),
    ),
    'photo' => PhotoPart([
      for (final i in j['items'] as List)
        (
          name: (i as Map<String, dynamic>)['name'] as String,
          confidence: i['confidence'] as String,
        ),
    ]),
    'education' => EducationPart([
      for (final e in j['items'] as List? ?? const [])
        EducationItem.fromJson(e as Map<String, dynamic>),
    ]),
    'challenges' => ChallengesPart([
      for (final c in j['items'] as List? ?? const [])
        ChatChallenge.fromJson(c as Map<String, dynamic>),
    ]),
    'reflection' => ReflectionPart(
      weekStart: j['weekStart'] as String,
      positives: [
        for (final p in j['positives'] as List? ?? const []) p as String,
      ],
      actionsDone: (j['actionsDone'] as int?) ?? 0,
      canAdjust: j['canAdjust'] == true,
      done: j['done'] == true,
    ),
    _ => null,
  };
}

class ChatChallenge {
  ChatChallenge.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      title = j['title'] as String,
      communityName = (j['communityName'] as String?) ?? '',
      statusLabel = (j['statusLabel'] as String?) ?? '',
      participating = j['participating'] == true,
      activeDays = (j['progress'] as Map?)?['activeDays'] as int?,
      targetDays = (j['progress'] as Map?)?['targetDays'] as int?;
  final String id, title, communityName, statusLabel;
  final bool participating;
  final int? activeDays, targetDays;
}

class EducationPart extends ChatPart {
  const EducationPart(this.items);
  final List<EducationItem> items;
}

class ChallengesPart extends ChatPart {
  const ChallengesPart(this.items);
  final List<ChatChallenge> items;
}

class ReflectionPart extends ChatPart {
  const ReflectionPart({
    required this.weekStart,
    required this.positives,
    required this.actionsDone,
    required this.canAdjust,
    required this.done,
  });
  final String weekStart;
  final List<String> positives;
  final int actionsDone;
  final bool canAdjust, done;
}

class TextPart extends ChatPart {
  const TextPart(this.text);
  final String text;
}

class StatisticPart extends ChatPart {
  StatisticPart.fromJson(Map<String, dynamic> j)
    : domain = j['domain'] as String,
      label = j['label'] as String,
      value = j['value'] as num?,
      unit = j['unit'] as String?,
      caption = (j['caption'] as String?) ?? '',
      days = (j['days'] as int?) ?? 7;
  final String domain, label, caption;
  final num? value;
  final String? unit;
  final int days;
}

class RecommendationsPart extends ChatPart {
  RecommendationsPart.fromJson(Map<String, dynamic> j)
    : runId = j['runId'] as String,
      kind = (j['kind'] as String?) ?? 'NUTRITION',
      hidden = j['hidden'] == true,
      items = [
        for (final r in (j['items'] as List? ?? const []))
          ChatRecommendation.fromJson(r as Map<String, dynamic>),
      ];
  final String runId, kind;
  final bool hidden;
  final List<ChatRecommendation> items;
}

class NoMatchPart extends ChatPart {
  const NoMatchPart(this.query, this.text);
  final String query, text;
}

class SafetyPart extends ChatPart {
  const SafetyPart({
    required this.code,
    required this.title,
    required this.text,
    required this.urgent,
  });
  final String code, title, text;
  final bool urgent;
}

class NoticePart extends ChatPart {
  const NoticePart(this.tone, this.text);
  final String tone, text;
}

class ConsentPart extends ChatPart {
  const ConsentPart(this.purpose, this.text);
  final String purpose, text;
}

class SuggestionsPart extends ChatPart {
  const SuggestionsPart(this.items);
  final List<Suggestion> items;
}

class LinkPart extends ChatPart {
  const LinkPart(this.label, this.target);
  final String label, target;
}

class DraftCandidate {
  DraftCandidate.fromJson(Map<String, dynamic> j)
    : key = j['key'] as String,
      kind = j['kind'] as String,
      name = j['name'] as String,
      source = (j['source'] as String?) ?? '',
      match = j['match'] as String?,
      url = j['url'] as String?,
      host = j['host'] as String?,
      preference = (j['preference'] as String?) ?? 'NO_MATCH_FOUND',
      per100g = ((j['per100g'] as Map<String, dynamic>?) ?? const {}).map(
        (k, v) => MapEntry(k, v as num?),
      );
  final String key, kind, name, source, preference;
  final String? match, url, host;
  final Map<String, num?> per100g;
  bool get excluded => preference == 'EXCLUDED';
  bool get fromWeb => kind == 'WEB';
  String get sourceLabel => switch (kind) {
    'TKPI' => 'TKPI',
    'WEB' => 'Web ${host ?? ''} · belum diverifikasi',
    _ => 'Katalogmu',
  };
}

class DraftItem {
  DraftItem.fromJson(Map<String, dynamic> j)
    : index = j['index'] as int,
      name = j['name'] as String,
      quantity = (j['quantity'] as num).toDouble(),
      unit = j['unit'] as String,
      unitLabel = j['unitLabel'] as String?,
      quantityStated = j['quantityStated'] == true,
      grams = (j['grams'] as num?)?.toDouble(),
      gramsBasis = j['gramsBasis'] as String?,
      photoConfidence = j['photoConfidence'] as String?,
      selected = j['selected'] as String?,
      webSearchStatus =
          (j['webSearch'] as Map<String, dynamic>?)?['status'] as String?,
      candidates = [
        for (final c in (j['candidates'] as List? ?? const []))
          DraftCandidate.fromJson(c as Map<String, dynamic>),
      ];
  final int index;
  final String name, unit;
  final String? unitLabel, gramsBasis, photoConfidence, selected;
  final String? webSearchStatus;
  bool get hasLocalMatch => candidates.any((c) => !c.fromWeb);
  int get webCount => candidates.where((c) => c.fromWeb).length;
  final bool quantityStated;
  final double quantity;
  final double? grams;
  final List<DraftCandidate> candidates;
  DraftCandidate? get selectedCandidate =>
      candidates.where((c) => c.key == selected).firstOrNull;
}

class MealDraft {
  MealDraft.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      status = j['status'] as String,
      source = j['source'] as String,
      category = j['category'] as String,
      consumedAt = DateTime.parse(j['consumedAt'] as String),
      localTime = (j['localTime'] as String?) ?? '',
      mealId = j['mealId'] as String?,
      version = j['version'] as int,
      items = [
        for (final i in j['items'] as List)
          DraftItem.fromJson(i as Map<String, dynamic>),
      ];
  final String id, status, source, category, localTime;
  final String? mealId;
  final int version;
  final DateTime consumedAt;
  final List<DraftItem> items;
  bool get open => status == 'PROPOSED';
}

class MealDraftPart extends ChatPart {
  const MealDraftPart(this.draftId, this.draft);
  final String draftId;
  final MealDraft? draft;
}

class MemoryProposal {
  MemoryProposal.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      content = j['content'] as String,
      kindLabel = (j['kindLabel'] as String?) ?? '',
      status = j['status'] as String;
  final String id, content, kindLabel, status;
}

class MemoryProposalPart extends ChatPart {
  const MemoryProposalPart(this.memoryId, this.memory);
  final String memoryId;
  final MemoryProposal? memory;
}

class PhotoPart extends ChatPart {
  const PhotoPart(this.items);
  final List<({String name, String confidence})> items;
}

class Basis {
  Basis.fromJson(Map<String, dynamic> j)
    : sources = [
        for (final s in (j['sources'] as List? ?? const []))
          (s as Map<String, dynamic>)['label'] as String,
      ],
      memories = [
        for (final m in (j['memories'] as List? ?? const []))
          (m as Map<String, dynamic>)['content'] as String,
      ],
      languageModel = (j['sources'] as List? ?? const []).any(
        (s) => (s as Map)['kind'] == 'LANGUAGE_MODEL',
      );
  final List<String> sources, memories;
  final bool languageModel;
  bool get isEmpty => sources.isEmpty && memories.isEmpty;
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.parts,
    this.text,
    this.clientMessageId,
    this.basis,
  });

  ChatMessage.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      role = j['role'] as String,
      text = j['text'] as String?,
      clientMessageId = j['clientMessageId'] as String?,
      basis = j['basis'] is Map<String, dynamic>
          ? Basis.fromJson(j['basis'] as Map<String, dynamic>)
          : null,
      parts = [
        for (final p in (j['parts'] as List? ?? const []))
          ?ChatPart.fromJson(p as Map<String, dynamic>),
      ];

  final String id, role;
  final String? text, clientMessageId;
  final Basis? basis;
  final List<ChatPart> parts;
  bool get isUser => role == 'USER';
}

class Exchange {
  Exchange.fromJson(Map<String, dynamic> j)
    : thread = ConversationThread.fromJson(j['thread'] as Map<String, dynamic>),
      user = ChatMessage.fromJson(j['userMessage'] as Map<String, dynamic>),
      assistant = ChatMessage.fromJson(
        j['assistantMessage'] as Map<String, dynamic>,
      );
  final ConversationThread thread;
  final ChatMessage user, assistant;
}

class ThreadDetail {
  ThreadDetail.fromJson(Map<String, dynamic> j)
    : thread = ConversationThread.fromJson(j['thread'] as Map<String, dynamic>),
      messages = [
        for (final m in j['messages'] as List)
          ChatMessage.fromJson(m as Map<String, dynamic>),
      ];
  final ConversationThread thread;
  final List<ChatMessage> messages;
}
