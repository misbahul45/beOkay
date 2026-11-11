import '../../../core/network/account_scoped_repository.dart';

class MemoryItem {
  MemoryItem.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      kind = j['kind'] as String,
      kindLabel = (j['kindLabel'] as String?) ?? '',
      content = j['content'] as String,
      status = j['status'] as String,
      version = (j['version'] as int?) ?? 1;
  final String id, kind, kindLabel, content, status;
  final int version;
  bool get active => status == 'ACTIVE';
  bool get proposed => status == 'PROPOSED';
}

class MemoryOverview {
  MemoryOverview.fromJson(Map<String, dynamic> j)
    : enabled = j['enabled'] == true,
      consentGiven = j['consentGiven'] == true,
      active = j['active'] == true,
      items = [
        for (final v in (j['items'] as List? ?? const []))
          MemoryItem.fromJson(v as Map<String, dynamic>),
      ];
  final bool enabled, consentGiven, active;
  final List<MemoryItem> items;
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
