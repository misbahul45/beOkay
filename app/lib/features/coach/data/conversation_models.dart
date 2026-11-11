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
    _ => null,
  };
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

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.parts,
    this.text,
    this.clientMessageId,
  });

  ChatMessage.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      role = j['role'] as String,
      text = j['text'] as String?,
      clientMessageId = j['clientMessageId'] as String?,
      parts = [
        for (final p in (j['parts'] as List? ?? const []))
          ?ChatPart.fromJson(p as Map<String, dynamic>),
      ];

  final String id, role;
  final String? text, clientMessageId;
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
