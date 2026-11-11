import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../../coaching/application/coaching_controller.dart';
import '../../community/application/community_controller.dart';
import '../data/notification_repository.dart';
import '../data/realtime_connector.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  final id = auth is AuthAuthenticated ? auth.user.id : null;
  return NotificationRepository(
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

final notificationsProvider = FutureProvider.autoDispose<NotificationPage>(
  (ref) => ref.watch(notificationRepositoryProvider).list(),
);

final notificationPreferencesProvider =
    FutureProvider.autoDispose<NotificationPreferences>(
      (ref) => ref.watch(notificationRepositoryProvider).preferences(),
    );

final realtimeConnectorProvider = Provider<RealtimeConnector>(
  (ref) => IoRealtimeConnector(),
);

class RealtimeState {
  const RealtimeState({this.connected = false, this.unread = 0});
  final bool connected;
  final int unread;
  RealtimeState copyWith({bool? connected, int? unread}) => RealtimeState(
    connected: connected ?? this.connected,
    unread: unread ?? this.unread,
  );
}

class LatestNotification extends Notifier<AppNotification?> {
  @override
  AppNotification? build() => null;
  void show(AppNotification n) => state = n;
  void clear() => state = null;
}

final latestNotificationProvider =
    NotifierProvider<LatestNotification, AppNotification?>(
      LatestNotification.new,
    );

final realtimeProvider = NotifierProvider<RealtimeController, RealtimeState>(
  RealtimeController.new,
);

class RealtimeController extends Notifier<RealtimeState> {
  RealtimeConnection? _conn;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _ping, _retry;
  int _attempt = 0;
  final _topics = <String>{};

  @override
  RealtimeState build() {
    final auth = ref.watch(authControllerProvider);
    ref.onDispose(_teardown);
    if (auth is! AuthAuthenticated) return const RealtimeState();
    Future.microtask(_connect);
    return const RealtimeState();
  }

  Future<void> _connect() async {
    if (!ref.mounted || _conn != null) return;
    final token = await ref.read(tokenStorageProvider).read();
    if (token == null || !ref.mounted) return;
    final base = Uri.parse(ref.read(apiClientProvider).baseUrl);
    final uri = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/api/me/realtime',
    );
    try {
      final c = await ref.read(realtimeConnectorProvider).connect(uri, token);
      if (!ref.mounted) {
        await c.close();
        return;
      }
      _conn = c;
      _attempt = 0;
      state = state.copyWith(connected: true);
      _sub = c.events.listen(_onEvent, onDone: _lost, onError: (_) => _lost());
      _ping = Timer.periodic(
        const Duration(seconds: 25),
        (_) => _conn?.send({'type': 'ping'}),
      );
      for (final t in _topics) {
        c.send({'type': 'subscribe', 'topic': t});
      }
    } catch (_) {
      _lost();
    }
  }

  void _lost() {
    _closeConnection();
    if (!ref.mounted) return;
    state = state.copyWith(connected: false);
    final delay = min(60, 2 << min(_attempt, 5));
    _attempt++;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: delay), _connect);
  }

  void _onEvent(Map<String, dynamic> e) {
    if (!ref.mounted) return;
    final unread = e['unread'];
    if (unread is int) state = state.copyWith(unread: unread);
    switch (e['type']) {
      case 'notification':
        final item = e['item'];
        if (item is Map<String, dynamic>) {
          ref
              .read(latestNotificationProvider.notifier)
              .show(AppNotification.fromJson(item));
        }
        ref.invalidate(notificationsProvider);
        ref.invalidate(homeHighlightProvider);
      case 'notifications.read':
        ref.invalidate(notificationsProvider);
      case 'coaching.updated':
        ref.invalidate(coachingOverviewProvider);
        ref.invalidate(reflectionProvider);
      case 'challenge.progress':
        final id = e['challengeId'];
        if (id is String) ref.invalidate(challengeDetailProvider(id));
        ref.invalidate(communityOverviewProvider);
        ref.invalidate(homeHighlightProvider);
      case 'leaderboard.changed':
        final id = e['challengeId'];
        if (id is String) ref.invalidate(leaderboardProvider(id));
    }
  }

  void setUnread(int n) => state = state.copyWith(unread: n);

  void subscribe(String topic) {
    if (_topics.add(topic)) _conn?.send({'type': 'subscribe', 'topic': topic});
  }

  void unsubscribe(String topic) {
    if (_topics.remove(topic)) {
      _conn?.send({'type': 'unsubscribe', 'topic': topic});
    }
  }

  void _closeConnection() {
    _ping?.cancel();
    _ping = null;
    _sub?.cancel();
    _sub = null;
    final c = _conn;
    _conn = null;
    if (c != null) unawaited(c.close().catchError((_) {}));
  }

  void _teardown() {
    _retry?.cancel();
    _retry = null;
    _closeConnection();
  }
}

String? routeForAction(String action, String? refId) => switch (action) {
  'OPEN_HOME' => '/home',
  'OPEN_LOG' => '/log',
  'OPEN_COACHING' => '/coaching',
  'OPEN_REFLECTION' => '/coaching/reflection',
  'OPEN_CHALLENGE' => refId == null ? '/community' : '/challenge/$refId',
  'OPEN_COMMUNITY' || 'OPEN_RECOGNITIONS' => '/community',
  'OPEN_REMINDERS' => '/reminders',
  'OPEN_GOALS' => '/goals',
  'OPEN_MEDICATIONS' => '/medications',
  _ => null,
};
