import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/error_messages.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/beokay_spark.dart';
import '../../../core/widgets/info_card.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/tab_root_header.dart';
import '../../nutrition/application/nutrition_controller.dart';
import '../../nutrition/presentation/scan/food_image_source.dart';
import '../../nutrition/presentation/scan/scan_widgets.dart';
import '../application/conversation_controller.dart';
import '../data/conversation_models.dart';
import 'chat_parts.dart';
import 'coach_history_sheet.dart';

const starters = [
  Suggestion(
    'Bagaimana aktivitasku minggu ini?',
    'Bagaimana aktivitasku minggu ini?',
  ),
  Suggestion('Cari info nasi goreng', 'Cari info nasi goreng'),
  Suggestion('Ide olahraga 15 menit', 'Ide olahraga ringan 15 menit'),
  Suggestion('Aku susah konsisten', 'Aku susah konsisten'),
];

class CoachScreen extends ConsumerStatefulWidget {
  const CoachScreen({super.key});
  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  final input = TextEditingController();
  final focus = FocusNode();
  final scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd(2));
  }

  void _jumpToEnd(int passes) {
    if (!mounted || passes == 0) return;
    if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd(passes - 1));
  }

  @override
  void dispose() {
    input.dispose();
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }

  ConversationController get _controller =>
      ref.read(conversationControllerProvider.notifier);

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) return;
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: MediaQuery.of(context).disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? input.text).trim();
    if (text.isEmpty) return;
    if (preset == null) input.clear();
    await _controller.send(text);
  }

  void _edit(String query) {
    input.text = query;
    input.selection = TextSelection.collapsed(offset: query.length);
    focus.requestFocus();
  }

  Future<void> _decide(ChatRecommendation r, {required bool accept}) async {
    try {
      await _controller.decide(r, accept: accept);
      if (mounted && accept) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              r.isActivity
                  ? 'Masuk rencana aktivitas. Catat sesinya saat sudah kamu lakukan.'
                  : 'Masuk rencana makan. Ini belum dicatat sebagai makanan yang dimakan.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(messageFor(e))));
      }
    }
  }

  final Set<String> _busy = {};

  Future<void> _guard(
    String id,
    Future<void> Function() job, {
    String? done,
  }) async {
    setState(() => _busy.add(id));
    try {
      await job();
      if (mounted && done != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(done)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  void _reviewDraft(MealDraft d) => showMealDraftEditor(
    context,
    draft: d,
    onSave:
        ({
          required String category,
          required DateTime consumedAt,
          required List<Map<String, dynamic>> items,
        }) async {
          await _controller.confirmDraft(
            d,
            category: category,
            consumedAt: consumedAt,
            items: items,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Tersimpan di catatan makan.')),
            );
          }
        },
  );

  Future<void> _pickPhoto() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final camera = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Ambil foto'),
              onTap: () => Navigator.of(sheet).pop(true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Pilih dari galeri'),
              onTap: () => Navigator.of(sheet).pop(false),
            ),
          ],
        ),
      ),
    );
    if (camera == null || !mounted) return;
    final bytes = await ref
        .read(foodImagePickerProvider)
        .capture(camera: camera);
    if (bytes == null || !mounted) return;
    if (!await confirmImageUpload(context, subject: 'makanan') || !mounted) {
      return;
    }
    try {
      final scan = await runWithProgress(
        context,
        'Mengenali makanan…',
        () => ref.read(nutritionRepositoryProvider).scanPhoto(bytes),
      );
      if (!mounted) return;
      if (scan.status == 'UNAVAILABLE' ||
          scan.status == 'NOT_FOOD' ||
          scan.items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              scan.status == 'UNAVAILABLE'
                  ? 'Pengenal foto sedang tidak tersedia. Tulis saja nama makanannya.'
                  : 'Tidak ada makanan yang terlihat jelas. Coba foto dari atas dengan cahaya cukup, atau tulis namanya.',
            ),
          ),
        );
        return;
      }
      await _controller.sendPhoto([
        for (final i in scan.items) (name: i.name, confidence: i.confidence),
      ]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(messageFor(e))));
      }
    }
  }

  Future<void> _webSearch(MealDraft d, DraftItem item) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Cari di web?'),
        content: Text(
          'Nama "${item.name}" dikirim ke layanan pencarian Firecrawl untuk mencari nilai gizinya. Hasilnya angka dari situs web dan belum diverifikasi beOkay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Cari'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _guard(d.id, () async {
      final status = await _controller.webLookup(d.id, item.index);
      if (!mounted) return;
      final message = switch (status) {
        'FOUND' => 'Ada hasil dari web. Pilih di "Periksa & simpan".',
        'NONE' => 'Tidak ada nilai gizi per 100 g yang bisa dipakai dari web.',
        'NOT_CONFIGURED' => 'Pencarian web belum aktif.',
        _ => 'Pencarian web sedang tidak tersedia.',
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    });
  }

  ChatExtras get _extras => ChatExtras(
    webSearch: _webSearch,
    busy: _busy,
    reviewDraft: _reviewDraft,
    discardDraft: (id) => _guard(id, () => _controller.discardDraft(id)),
    openMeal: (id) => context.push('${Routes.meals}/$id'),
    answerMemory: (id, remember) => _guard(
      id,
      () => _controller.answerMemory(id, remember: remember),
      done: remember
          ? 'Diingat. Kamu bisa mengubahnya di Memori & personalisasi.'
          : null,
    ),
    manageMemory: () => context.push(Routes.memory),
  );

  void _openLink(String target) => switch (target) {
    'INSIGHTS' => context.go(Routes.insights),
    'LOG' => context.go(Routes.log),
    'LOG_MEAL' => context.push(Routes.addMeal),
    'CONSENT' => context.push(Routes.consentManagement),
    _ => null,
  };

  SparkState _spark(ChatState s) {
    if (s.sending) return SparkState.thinking;
    if (s.pending?.failed ?? false) return SparkState.error;
    final last = s.messages.isEmpty ? null : s.messages.last;
    if (last == null || last.isUser) return SparkState.idle;
    if (last.parts.any((p) => p is SafetyPart || p is ConsentPart)) {
      return SparkState.neutral;
    }
    if (last.parts.any(
      (p) => p is RecommendationsPart && p.items.any((i) => i.offered),
    )) {
      return SparkState.responding;
    }
    return SparkState.idle;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(conversationControllerProvider);
    ref.listen(conversationControllerProvider, (prev, next) {
      if (prev?.messages.length != next.messages.length ||
          prev?.pending?.id != next.pending?.id ||
          prev?.threadId != next.threadId) {
        _toBottom();
      }
    });
    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              state: _spark(s),
              onHistory: () => showCoachHistory(context),
            ),
            Expanded(
              child: s.isEmpty
                  ? _EmptyState(restoring: s.restoring, onPick: (m) => _send(m))
                  : _Thread(
                      state: s,
                      scroll: scroll,
                      onSend: (m) => _send(m),
                      onEdit: _edit,
                      onDecide: _decide,
                      onLink: _openLink,
                      onRetry: _controller.retry,
                      onDiscard: _controller.discardPending,
                      extras: _extras,
                    ),
            ),
            _Composer(
              controller: input,
              focus: focus,
              sending: s.sending,
              onSend: () => _send(),
              onPhoto: _pickPhoto,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.onHistory});
  final SparkState state;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.page,
      AppSpacing.xs,
      AppSpacing.xs,
      AppSpacing.xxs,
    ),
    child: Row(
      children: [
        BeOkaySpark(size: 40, state: state),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text('Asisten', style: AppTypography.heading),
              ),
              Text(
                'Saran selalu menunggu persetujuanmu',
                style: AppTypography.caption,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Riwayat & rencana',
          onPressed: onHistory,
          icon: Icon(Icons.history_rounded, color: AppColors.brand),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surface,
            side: BorderSide(color: AppColors.border),
          ),
        ),
        const ProfileAction(),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.restoring, required this.onPick});
  final bool restoring;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpacing.page),
    children: [
      Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.cream,
          borderRadius: BorderRadius.circular(AppRadius.hero),
        ),
        child: Column(
          children: [
            const BeOkaySpark(size: 72),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Mau mulai dari mana?',
              style: AppTypography.title,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Tanya soal catatanmu, cari makanan, atau minta ide aktivitas.',
              style: AppTypography.secondary,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      if (restoring)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: LinearProgressIndicator(),
        ),
      const SizedBox(height: AppSpacing.sm),
      for (final s in starters)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: BorderSide(color: AppColors.border),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () => onPick(s.message),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppSpacing.minTouchTarget,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(s.label, style: AppTypography.body)),
                      Icon(
                        Icons.north_east_rounded,
                        size: 18,
                        color: AppColors.brand,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

Widget _userBubble(ChatMessage m) {
  final photo = m.parts.whereType<PhotoPart>().firstOrNull;
  return photo == null
      ? UserBubble(text: m.text ?? '')
      : PhotoBubble(items: photo.items);
}

class ChatExtras {
  const ChatExtras({
    required this.webSearch,
    required this.busy,
    required this.reviewDraft,
    required this.discardDraft,
    required this.openMeal,
    required this.answerMemory,
    required this.manageMemory,
  });
  final Set<String> busy;
  final void Function(MealDraft draft, DraftItem item) webSearch;
  final ValueChanged<MealDraft> reviewDraft;
  final ValueChanged<String> discardDraft, openMeal;
  final void Function(String id, bool remember) answerMemory;
  final VoidCallback manageMemory;
}

class _Thread extends StatelessWidget {
  const _Thread({
    required this.extras,
    required this.state,
    required this.scroll,
    required this.onSend,
    required this.onEdit,
    required this.onDecide,
    required this.onLink,
    required this.onRetry,
    required this.onDiscard,
  });

  final ChatExtras extras;
  final ChatState state;
  final ScrollController scroll;
  final ValueChanged<String> onSend, onEdit, onLink;
  final DecideCallback onDecide;
  final VoidCallback onRetry, onDiscard;

  @override
  Widget build(BuildContext context) {
    final msgs = state.messages;
    final p = state.pending;
    return ListView.builder(
      controller: scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.xs,
        AppSpacing.page,
        AppSpacing.md,
      ),
      itemCount: msgs.length + (p == null ? 0 : 1),
      itemBuilder: (context, i) {
        if (i == msgs.length) {
          return _PendingTurn(
            pending: p!,
            onRetry: onRetry,
            onDiscard: onDiscard,
          );
        }
        final m = msgs[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: m.isUser
              ? _userBubble(m)
              : _AssistantTurn(
                  extras: extras,
                  message: m,
                  isLast: i == msgs.length - 1 && p == null,
                  busy: state.busyRecommendations,
                  onSend: onSend,
                  onEdit: onEdit,
                  onDecide: onDecide,
                  onLink: onLink,
                ),
        );
      },
    );
  }
}

class _AssistantTurn extends StatelessWidget {
  const _AssistantTurn({
    required this.extras,
    required this.message,
    required this.isLast,
    required this.busy,
    required this.onSend,
    required this.onEdit,
    required this.onDecide,
    required this.onLink,
  });

  final ChatExtras extras;
  final ChatMessage message;
  final bool isLast;
  final Set<String> busy;
  final ValueChanged<String> onSend, onEdit, onLink;
  final DecideCallback onDecide;

  @override
  Widget build(BuildContext context) {
    final links = message.parts.whereType<LinkPart>().toList();
    final children = <Widget>[];
    for (final part in message.parts) {
      final w = switch (part) {
        TextPart(:final text) => AssistantBubble(text: text),
        StatisticPart() => StatisticCard(part: part),
        RecommendationsPart() => RecommendationGroup(
          part: part,
          busy: busy,
          onDecide: onDecide,
        ),
        NoMatchPart() => NoMatchCard(part: part, onEdit: onEdit),
        SafetyPart() => SafetyCard(part: part),
        NoticePart(:final tone, :final text) => InfoCard(
          tone: switch (tone) {
            'error' => InfoTone.error,
            'warning' => InfoTone.warning,
            _ => InfoTone.info,
          },
          text: text,
        ),
        ConsentPart(:final text) => InfoCard(
          tone: InfoTone.warning,
          title: 'Persetujuan diperlukan',
          text: text,
          action: PillButton(
            label: 'Buka persetujuan',
            kind: PillButtonKind.secondary,
            expand: false,
            onPressed: () => context.push(Routes.consentManagement),
          ),
        ),
        SuggestionsPart() => null,
        LinkPart() => null,
        PhotoPart() => null,
        MealDraftPart(:final draft) =>
          draft == null
              ? null
              : MealDraftCard(
                  draft: draft,
                  busy: extras.busy.contains(draft.id),
                  onReview: () => extras.reviewDraft(draft),
                  onDiscard: () => extras.discardDraft(draft.id),
                  onOpenMeal: () => extras.openMeal(draft.mealId ?? draft.id),
                  onWebSearch: (item) => extras.webSearch(draft, item),
                ),
        MemoryProposalPart(:final memory) =>
          memory == null
              ? null
              : MemoryProposalCard(
                  proposal: memory,
                  busy: extras.busy.contains(memory.id),
                  onAnswer: (r) => extras.answerMemory(memory.id, r),
                ),
      };
      if (w != null) children.add(w);
    }
    final suggestions = isLast
        ? message.parts.whereType<SuggestionsPart>().expand((p) => p.items)
        : const <Suggestion>[];
    if (suggestions.isNotEmpty || links.isNotEmpty) {
      children.add(
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final s in suggestions)
              ChatChip(label: s.label, onTap: () => onSend(s.message)),
            for (final l in links)
              ChatChip(
                label: l.label,
                icon: Icons.chevron_right_rounded,
                onTap: () => onLink(l.target),
              ),
          ],
        ),
      );
    }
    final basis = message.basis;
    if (basis != null && !basis.isEmpty) {
      children.add(BasisLink(basis: basis, onManage: extras.manageMemory));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          children[i],
        ],
      ],
    );
  }
}

class _PendingTurn extends StatelessWidget {
  const _PendingTurn({
    required this.pending,
    required this.onRetry,
    required this.onDiscard,
  });
  final PendingMessage pending;
  final VoidCallback onRetry, onDiscard;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (pending.photo case final photo?)
        PhotoBubble(items: photo, faded: !pending.failed)
      else
        UserBubble(text: pending.text, faded: !pending.failed),
      const SizedBox(height: AppSpacing.xs),
      if (pending.failed)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ErrorBanner(messageFor(pending.failure!)),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                PillButton(
                  label: 'Coba lagi',
                  icon: Icons.refresh_rounded,
                  expand: false,
                  onPressed: onRetry,
                ),
                PillButton(
                  label: 'Batalkan',
                  kind: PillButtonKind.ghost,
                  expand: false,
                  onPressed: onDiscard,
                ),
              ],
            ),
          ],
        )
      else
        Semantics(
          liveRegion: true,
          child: Row(
            children: [
              const BeOkaySpark(size: 28, state: SparkState.thinking),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  'Sedang menyiapkan jawaban…',
                  style: AppTypography.secondary,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focus,
    required this.sending,
    required this.onSend,
    required this.onPhoto,
  });
  final TextEditingController controller;
  final FocusNode focus;
  final bool sending;
  final VoidCallback onSend, onPhoto;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.sm,
      AppSpacing.xs,
      AppSpacing.sm,
      AppSpacing.xs,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IconButton(
          tooltip: 'Foto makanan',
          onPressed: sending ? null : onPhoto,
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surface,
            side: BorderSide(color: AppColors.border),
            fixedSize: const Size(48, 48),
          ),
          icon: Icon(Icons.photo_camera_outlined, color: AppColors.brand),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focus,
            minLines: 1,
            maxLines: 4,
            maxLength: 1000,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            decoration: InputDecoration(
              hintText: 'Tulis pesan…',
              counterText: '',
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide(color: AppColors.focus, width: 2),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        IconButton.filled(
          tooltip: 'Kirim',
          onPressed: sending ? null : onSend,
          style: IconButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            fixedSize: const Size(48, 48),
          ),
          icon: const Icon(Icons.arrow_upward_rounded),
        ),
      ],
    ),
  );
}
