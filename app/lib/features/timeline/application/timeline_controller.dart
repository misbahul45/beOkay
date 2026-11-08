import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../../consent/application/consent_controller.dart';
import '../../preferences/application/preferences_controller.dart';
import '../data/timeline_models.dart';
import '../data/timeline_repository.dart';

final timelineRepositoryProvider = Provider<TimelineRepository>((ref) => TimelineRepository(ref.watch(apiClientProvider)));

/// Filter state is part of the request, so what chips show always equals what the API returned.
class LogFilter {
  const LogFilter({this.domain = 'all', this.date, this.archived = false});

  final String domain;
  final String? date;
  final bool archived;

  LogFilter copyWith({String? domain, Object? date = _keep, bool? archived}) => LogFilter(
    domain: domain ?? this.domain,
    date: identical(date, _keep) ? this.date : date as String?,
    archived: archived ?? this.archived,
  );

  static const _keep = Object();
}

class LogFeed {
  const LogFeed({this.items = const [], this.nextCursor, this.timezone, this.loadingMore = false, this.moreError});

  final List<TimelineItem> items;
  final String? nextCursor;
  final String? timezone;
  final bool loadingMore;
  final Object? moreError;

  LogFeed copyWith({List<TimelineItem>? items, String? nextCursor, bool clearCursor = false, bool? loadingMore, Object? moreError, bool clearMoreError = false}) => LogFeed(
    items: items ?? this.items,
    nextCursor: clearCursor ? null : nextCursor ?? this.nextCursor,
    timezone: timezone,
    loadingMore: loadingMore ?? this.loadingMore,
    moreError: clearMoreError ? null : moreError ?? this.moreError,
  );
}

final logFilterProvider = NotifierProvider.autoDispose<LogFilterNotifier, LogFilter>(LogFilterNotifier.new);

class LogFilterNotifier extends Notifier<LogFilter> {
  @override
  LogFilter build() => const LogFilter();

  void set(LogFilter filter) => state = filter;
}

/// First page loads through [AsyncNotifier.build]; further pages append through
/// the stable cursor. Rebuilds (filter, account, consent change) start from zero,
/// so one account's rows can never be mixed into another's list.
final logFeedProvider = AsyncNotifierProvider.autoDispose<LogFeedController, LogFeed>(LogFeedController.new);

class LogFeedController extends AsyncNotifier<LogFeed> {
  @override
  Future<LogFeed> build() async {
    final filter = ref.watch(logFilterProvider);
    if (ref.watch(authControllerProvider) is! AuthAuthenticated) return const LogFeed();
    await Future.wait([ref.watch(consentControllerProvider.future), ref.watch(preferencesControllerProvider.future)]);
    final page = await ref.read(timelineRepositoryProvider).list(domain: filter.domain, date: filter.date, archived: filter.archived);
    return LogFeed(items: page.items, nextCursor: page.nextCursor, timezone: page.timezone);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.nextCursor == null || current.loadingMore) return;
    final filter = ref.read(logFilterProvider);
    state = AsyncData(current.copyWith(loadingMore: true, clearMoreError: true));
    try {
      final page = await ref.read(timelineRepositoryProvider).list(domain: filter.domain, date: filter.date, archived: filter.archived, cursor: current.nextCursor);
      if (!ref.mounted) return;
      final seen = {for (final item in current.items) '${item.domain}:${item.recordId}'};
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...page.items.where((item) => !seen.contains('${item.domain}:${item.recordId}'))],
          nextCursor: page.nextCursor,
          clearCursor: page.nextCursor == null,
          loadingMore: false,
        ),
      );
    } catch (error) {
      if (!ref.mounted) return;
      state = AsyncData(current.copyWith(loadingMore: false, moreError: error));
    }
  }
}
