import 'dart:convert';

import '../../../core/offline/offline_queue.dart';
import '../data/health_source.dart';

class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.source,
    required this.metric,
    required this.items,
    required this.createdAt,
    this.attempts = 0,
  });
  final String id, source;
  final WearableMetric metric;
  final List<Map<String, dynamic>> items;
  final DateTime createdAt;
  final int attempts;

  OutboxEntry bumped() => OutboxEntry(
    id: id,
    source: source,
    metric: metric,
    items: items,
    createdAt: createdAt,
    attempts: attempts + 1,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source,
    'metric': metric.name,
    'items': items,
    'createdAt': createdAt.toIso8601String(),
    'attempts': attempts,
  };

  static OutboxEntry? fromJson(Map<String, dynamic> j) {
    final metric = WearableMetric.values
        .where((m) => m.name == j['metric'])
        .firstOrNull;
    final created = DateTime.tryParse((j['createdAt'] as String?) ?? '');
    if (metric == null || created == null || j['id'] is! String) return null;
    return OutboxEntry(
      id: j['id'] as String,
      source: (j['source'] as String?) ?? 'health_connect',
      metric: metric,
      items: [
        for (final i in (j['items'] as List? ?? const []))
          (i as Map).cast<String, dynamic>(),
      ],
      createdAt: created,
      attempts: (j['attempts'] as num?)?.toInt() ?? 0,
    );
  }
}

class SyncStore {
  SyncStore(this._store, this.accountId);
  final KeyValueStore _store;
  final String accountId;

  static const maxOutboxEntries = 24;
  static const maxOutboxAttempts = 8;

  String get _cursorKey => 'beokay.devsync.cursor.$accountId';
  String get _outboxKey => 'beokay.devsync.outbox.$accountId';

  Future<Map<String, String>> _cursors() async {
    try {
      final raw = await _store.read(_cursorKey);
      if (raw == null) return {};
      return (jsonDecode(raw) as Map).cast<String, String>();
    } catch (_) {
      return {};
    }
  }

  String _k(String source, WearableMetric m) => '$source:${m.name}';

  Future<DateTime?> cursor(String source, WearableMetric metric) async =>
      DateTime.tryParse((await _cursors())[_k(source, metric)] ?? '');

  Future<void> setCursor(
    String source,
    WearableMetric metric,
    DateTime at,
  ) async {
    final all = await _cursors();
    all[_k(source, metric)] = at.toUtc().toIso8601String();
    await _store.write(_cursorKey, jsonEncode(all));
  }

  Future<void> resetCursor(String source, WearableMetric metric) async {
    final all = await _cursors()
      ..remove(_k(source, metric));
    await _store.write(_cursorKey, jsonEncode(all));
  }

  Future<List<OutboxEntry>> outbox() async {
    try {
      final raw = await _store.read(_outboxKey);
      if (raw == null) return const [];
      return [
        for (final e in (jsonDecode(raw) as List))
          ?OutboxEntry.fromJson((e as Map).cast<String, dynamic>()),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveOutbox(List<OutboxEntry> entries) => entries.isEmpty
      ? _store.delete(_outboxKey)
      : _store.write(
          _outboxKey,
          jsonEncode([for (final e in entries) e.toJson()]),
        );

  Future<int> enqueue(OutboxEntry entry) async {
    final all = [...await outbox(), entry];
    var dropped = 0;
    while (all.length > maxOutboxEntries) {
      all.removeAt(0);
      dropped++;
    }
    await saveOutbox(all);
    return dropped;
  }

  Future<void> clear() async {
    await _store.delete(_cursorKey);
    await _store.delete(_outboxKey);
  }

  Future<void> clearOutbox() => _store.delete(_outboxKey);
}
