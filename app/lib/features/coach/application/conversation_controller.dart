import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ids/record_id.dart';
import '../../insights/application/insights_controller.dart';
import '../../memory/application/memory_controller.dart';
import '../../today/application/today_controller.dart';
import '../data/conversation_models.dart';
import 'coach_controller.dart';

typedef PhotoItem = ({String name, String confidence});

class PendingMessage {
  const PendingMessage({
    required this.id,
    required this.text,
    this.photo,
    this.failure,
  });
  final String id, text;
  final List<PhotoItem>? photo;
  final Object? failure;
  bool get failed => failure != null;
}

class ChatState {
  const ChatState({
    required this.threadId,
    this.messages = const [],
    this.pending,
    this.restoring = false,
    this.busyRecommendations = const {},
  });

  final String threadId;
  final List<ChatMessage> messages;
  final PendingMessage? pending;
  final bool restoring;
  final Set<String> busyRecommendations;

  bool get sending => pending != null && !pending!.failed;
  bool get isEmpty => messages.isEmpty && pending == null;

  ChatState copyWith({
    String? threadId,
    List<ChatMessage>? messages,
    PendingMessage? pending,
    bool clearPending = false,
    bool? restoring,
    Set<String>? busyRecommendations,
  }) => ChatState(
    threadId: threadId ?? this.threadId,
    messages: messages ?? this.messages,
    pending: clearPending ? null : (pending ?? this.pending),
    restoring: restoring ?? this.restoring,
    busyRecommendations: busyRecommendations ?? this.busyRecommendations,
  );
}

const restoreWindow = Duration(hours: 24);

class ConversationController extends Notifier<ChatState> {
  final Map<String, String> _ops = {};

  @override
  ChatState build() {
    ref.watch(coachRepositoryProvider);
    Future.microtask(_restore);
    return ChatState(threadId: newRecordId(), restoring: true);
  }

  Future<void> _restore() async {
    try {
      final repo = ref.read(coachRepositoryProvider);
      final threads = await repo.threads();
      final recent = threads.where(
        (t) =>
            t.lastMessageAt != null &&
            DateTime.now().difference(t.lastMessageAt!) < restoreWindow,
      );
      if (!ref.mounted || recent.isEmpty || !state.isEmpty) return;
      final detail = await repo.thread(recent.first.id);
      if (!ref.mounted || !state.isEmpty) return;
      state = state.copyWith(
        threadId: detail.thread.id,
        messages: detail.messages,
      );
    } catch (_) {
    } finally {
      if (ref.mounted) state = state.copyWith(restoring: false);
    }
  }

  Future<void> send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || state.sending) return;
    await _deliver(PendingMessage(id: newRecordId(), text: text));
  }

  Future<void> retry() async {
    final p = state.pending;
    if (p == null || !p.failed) return;
    await _deliver(PendingMessage(id: p.id, text: p.text, photo: p.photo));
  }

  Future<void> sendPhoto(List<PhotoItem> items) async {
    if (items.isEmpty || state.sending) return;
    await _deliver(
      PendingMessage(id: newRecordId(), text: 'Foto makanan', photo: items),
    );
  }

  void discardPending() => state = state.copyWith(clearPending: true);

  Future<void> _deliver(PendingMessage p) async {
    final threadId = state.threadId;
    state = state.copyWith(pending: p, restoring: false);
    try {
      final ex = await ref
          .read(coachRepositoryProvider)
          .send(threadId, clientMessageId: p.id, text: p.text, photo: p.photo);
      if (!ref.mounted || state.threadId != threadId) return;
      final known = {for (final m in state.messages) m.id};
      state = state.copyWith(
        messages: [
          ...state.messages,
          if (!known.contains(ex.user.id)) ex.user,
          if (!known.contains(ex.assistant.id)) ex.assistant,
        ],
        clearPending: true,
      );
      if (ex.assistant.parts.any((x) => x is RecommendationsPart)) {
        ref.invalidate(conversationThreadsProvider);
      }
    } catch (e) {
      if (!ref.mounted || state.threadId != threadId) return;
      state = state.copyWith(
        pending: PendingMessage(
          id: p.id,
          text: p.text,
          photo: p.photo,
          failure: e,
        ),
      );
    }
  }

  void startNew() {
    _ops.clear();
    state = ChatState(threadId: newRecordId());
  }

  Future<void> open(String threadId) async {
    final detail = await ref.read(coachRepositoryProvider).thread(threadId);
    if (!ref.mounted) return;
    _ops.clear();
    state = ChatState(threadId: detail.thread.id, messages: detail.messages);
  }

  Future<void> refresh() async {
    if (state.messages.isEmpty) return;
    final id = state.threadId;
    final detail = await ref.read(coachRepositoryProvider).thread(id);
    if (!ref.mounted || state.threadId != id) return;
    state = state.copyWith(messages: detail.messages);
  }

  Future<void> remove(String threadId) async {
    await ref.read(coachRepositoryProvider).deleteThread(threadId);
    if (!ref.mounted) return;
    if (state.threadId == threadId) startNew();
    ref.invalidate(conversationThreadsProvider);
  }

  Future<void> decide(ChatRecommendation r, {required bool accept}) async {
    final op = _ops.putIfAbsent('${r.id}:${accept ? 'a' : 'r'}', newRecordId);
    state = state.copyWith(
      busyRecommendations: {...state.busyRecommendations, r.id},
    );
    try {
      await ref
          .read(coachRepositoryProvider)
          .decideItem(r, accept: accept, operationId: op);
      ref.invalidate(plannedMealsProvider);
      ref.invalidate(activityPlansProvider);
      await refresh();
    } finally {
      if (ref.mounted) {
        state = state.copyWith(
          busyRecommendations: {...state.busyRecommendations}..remove(r.id),
        );
      }
    }
  }

  Future<String> confirmDraft(
    MealDraft draft, {
    required String category,
    required DateTime consumedAt,
    required List<Map<String, dynamic>> items,
  }) async {
    final mealId = await ref
        .read(coachRepositoryProvider)
        .confirmDraft(
          draft,
          category: category,
          consumedAt: consumedAt,
          items: items,
        );
    ref.invalidate(todayProvider);
    ref.invalidate(dailyInsightsProvider);
    await refresh();
    return mealId;
  }

  Future<String> webLookup(String draftId, int index) async {
    final status = await ref
        .read(coachRepositoryProvider)
        .webSearchDraftItem(draftId, index);
    await refresh();
    return status;
  }

  Future<void> discardDraft(String id) async {
    await ref.read(coachRepositoryProvider).discardDraft(id);
    await refresh();
  }

  Future<void> answerMemory(String id, {required bool remember}) async {
    final repo = ref.read(coachRepositoryProvider);
    if (remember) {
      await repo.confirmMemory(id);
    } else {
      await repo.dismissMemory(id);
    }
    ref.invalidate(memoryOverviewProvider);
    await refresh();
  }
}

final conversationControllerProvider =
    NotifierProvider<ConversationController, ChatState>(
      ConversationController.new,
    );

final conversationThreadsProvider =
    FutureProvider.autoDispose<List<ConversationThread>>(
      (ref) => ref.watch(coachRepositoryProvider).threads(),
    );
