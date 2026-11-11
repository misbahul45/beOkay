import '../../../core/network/account_scoped_repository.dart';

class AppNotification {
  AppNotification.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      kind = j['kind'] as String,
      title = j['title'] as String,
      body = j['body'] as String,
      action = j['action'] as String,
      refId = j['refId'] as String?,
      read = j['read'] == true,
      createdAt = DateTime.parse(j['createdAt'] as String).toLocal();
  final String id, kind, title, body, action;
  final String? refId;
  final bool read;
  final DateTime createdAt;
}

class NotificationPage {
  NotificationPage(this.items, this.nextCursor, this.unread);
  final List<AppNotification> items;
  final String? nextCursor;
  final int unread;
}

class NotificationPreferences {
  NotificationPreferences.fromJson(Map<String, dynamic> j)
    : pushEnabled = j['pushEnabled'] != false,
      mutedKinds = {
        for (final k in j['mutedKinds'] as List? ?? const []) k as String,
      },
      pushConfigured = j['pushConfigured'] == true,
      devices = (j['devices'] as int?) ?? 0;
  final bool pushEnabled, pushConfigured;
  final Set<String> mutedKinds;
  final int devices;
}

class NotificationRepository extends AccountScopedRepository {
  NotificationRepository(super.api, {required super.isCurrentAccount});

  Future<NotificationPage> list({String? cursor}) async {
    final j = (await api.get(
      '/api/me/notifications?limit=30${cursor == null ? '' : '&cursor=$cursor'}',
    )).object;
    return NotificationPage(
      [
        for (final v in j['items'] as List)
          AppNotification.fromJson(v as Map<String, dynamic>),
      ],
      j['nextCursor'] as String?,
      (j['unread'] as int?) ?? 0,
    );
  }

  Future<int> markRead(String id) async =>
      ((await write(
            'POST',
            '/api/me/notifications/$id/read',
            {},
          )).object['unread']
          as int?) ??
      0;

  Future<void> markAllRead() async =>
      write('POST', '/api/me/notifications/read-all', {});

  Future<NotificationPreferences> preferences() async =>
      NotificationPreferences.fromJson(
        (await api.get('/api/me/notification-preferences')).object,
      );

  Future<NotificationPreferences> updatePreferences({
    bool? pushEnabled,
    Set<String>? mutedKinds,
  }) async => NotificationPreferences.fromJson(
    (await write('PATCH', '/api/me/notification-preferences', {
      'pushEnabled': ?pushEnabled,
      if (mutedKinds != null) 'mutedKinds': mutedKinds.toList(),
    })).object,
  );
}
