import '../../../core/network/account_scoped_repository.dart';

class MemoryItem {
  MemoryItem.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      kind = j['kind'] as String,
      kindLabel = (j['kindLabel'] as String?) ?? '',
      content = j['content'] as String,
      status = j['status'] as String,
      version = (j['version'] as int?) ?? 1,
      expiresAt = DateTime.tryParse((j['expiresAt'] as String?) ?? ''),
      confirmedAt = DateTime.tryParse((j['confirmedAt'] as String?) ?? ''),
      memoryType = (j['memoryType'] as String?) ?? 'FACT',
      sourceType = (j['sourceType'] as String?) ?? '',
      conflictState = (j['conflictState'] as String?) ?? 'NONE',
      paused = j['paused'] == true,
      pauseReason = j['pauseReason'] as String?;
  final String id, kind, kindLabel, content, status;
  final String memoryType, sourceType, conflictState;
  final DateTime? confirmedAt;
  final bool paused;
  final String? pauseReason;
  bool get conflicting => conflictState == 'CONFLICTING';
  bool get derived => sourceType == 'DERIVED';
  String get typeLabel => switch (memoryType) {
    'ROUTINE' => 'Rutinitas',
    'PREFERENCE' => 'Preferensi',
    'BARRIER' => 'Hambatan',
    'EPISODE' => 'Keadaan sementara',
    'DERIVED' => 'Dari catatanmu',
    _ => kindLabel,
  };
  final DateTime? expiresAt;
  bool get temporary => kind == 'HEALTH_EVENT';
  final int version;
  bool get active => status == 'ACTIVE';
  bool get proposed => status == 'PROPOSED';
}

class MemoryOverview {
  MemoryOverview.fromJson(Map<String, dynamic> j)
    : enabled = j['enabled'] == true,
      consentGiven = j['consentGiven'] == true,
      active = j['active'] == true,
      items = _list(j['items']),
      paused = _list(j['paused']),
      conflicts = _list(j['conflicts']),
      proposals = _list(j['proposals']);
  final bool enabled, consentGiven, active;
  final List<MemoryItem> items, paused, conflicts, proposals;

  static List<MemoryItem> _list(Object? v) => [
    for (final e in (v as List? ?? const []))
      MemoryItem.fromJson(e as Map<String, dynamic>),
  ];

  MemoryItem? activeFor(MemoryItem proposal) {
    for (final m in items) {
      if (m.kind == proposal.kind && m.conflicting) return m;
    }
    return null;
  }
}

class MemoryRevisionEntry {
  MemoryRevisionEntry.fromJson(Map<String, dynamic> j)
    : change = j['change'] as String,
      content = (j['content'] as String?) ?? '',
      reason = j['reason'] as String?,
      at = DateTime.parse(j['at'] as String);
  final String change, content;
  final String? reason;
  final DateTime at;
  String get label => switch (change) {
    'PROPOSED' => 'diusulkan',
    'CONFIRMED' => 'dikonfirmasi',
    'CORRECTED' => 'dikoreksi',
    'PAUSED' => 'dijeda',
    'RESUMED' => 'dilanjutkan',
    'DISMISSED' => 'ditolak',
    'SUPERSEDED' => 'diganti',
    'CONFLICT' => 'bertentangan',
    _ => change.toLowerCase(),
  };
}

class PersonalizationSummary {
  PersonalizationSummary.fromJson(Map<String, dynamic> j)
    : version = (j['version'] as int?) ?? 0,
      dislikedTerms = [
        for (final v in (j['dislikedTerms'] as List? ?? const []))
          (v as Map<String, dynamic>)['term'] as String,
      ],
      likedTerms = [
        for (final v in (j['likedTerms'] as List? ?? const []))
          (v as Map<String, dynamic>)['term'] as String,
      ];
  final int version;
  final List<String> dislikedTerms, likedTerms;
  bool get isEmpty => dislikedTerms.isEmpty && likedTerms.isEmpty;
}

class MemoryRepository extends AccountScopedRepository {
  MemoryRepository(super.api, {required super.isCurrentAccount});

  Future<MemoryOverview> overview() async =>
      MemoryOverview.fromJson((await api.get('/api/me/memories')).object);

  Future<MemoryOverview> setEnabled(bool enabled) async =>
      MemoryOverview.fromJson(
        (await write('PATCH', '/api/me/memory-preferences', {
          'enabled': enabled,
        })).object,
      );

  Future<MemoryItem> confirm(String id) async => MemoryItem.fromJson(
    (await write('POST', '/api/me/memories/$id/confirm', {})).object,
  );

  Future<MemoryItem> dismiss(String id) async => MemoryItem.fromJson(
    (await write('POST', '/api/me/memories/$id/dismiss', {})).object,
  );

  Future<MemoryItem> update(MemoryItem m, String content) async =>
      MemoryItem.fromJson(
        (await write('PATCH', '/api/me/memories/${m.id}', {
          'content': content,
          'expectedVersion': m.version,
        })).object,
      );

  Future<MemoryItem> pause(String id) async => MemoryItem.fromJson(
    (await write('POST', '/api/me/memories/$id/pause', {})).object,
  );

  Future<MemoryItem> resume(String id) async => MemoryItem.fromJson(
    (await write('POST', '/api/me/memories/$id/resume', {})).object,
  );

  Future<List<MemoryRevisionEntry>> history(String id) async => [
    for (final e
        in ((await api.get('/api/me/memories/$id/history')).object['items']
                as List? ??
            const []))
      MemoryRevisionEntry.fromJson(e as Map<String, dynamic>),
  ];

  Future<void> remove(String id) async =>
      write('DELETE', '/api/me/memories/$id', {});

  Future<void> removeAll() async => write('DELETE', '/api/me/memories', {});

  Future<PersonalizationSummary> personalization() async =>
      PersonalizationSummary.fromJson(
        (await api.get('/api/me/personalization')).object,
      );

  Future<void> resetPersonalization() async =>
      write('DELETE', '/api/me/personalization', {});
}
