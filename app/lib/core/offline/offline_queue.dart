import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Penyimpanan kunci-nilai terenkripsi (Android Keystore / iOS Keychain lewat flutter_secure_storage).
abstract interface class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureKeyValueStore implements KeyValueStore {
  SecureKeyValueStore([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

enum QueueState { savedLocal, syncing, syncFailed, conflict, needsReview }

/// Operasi yang menunggu dikirim. [payload] sama persis dengan isi permintaan online.
class QueuedOperation {
  const QueuedOperation({
    required this.operationId,
    required this.domain,
    required this.recordId,
    required this.operationType,
    required this.payload,
    required this.createdAt,
    this.parentId,
    this.state = QueueState.savedLocal,
    this.errorCode,
    this.errorMessage,
  });

  final String operationId;
  final String domain; // meal|glucose|activity|medication_intake|goal_checkin
  final String recordId;
  final String operationType; // create
  final String? parentId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final QueueState state;
  final String? errorCode;
  final String? errorMessage;

  QueuedOperation copyWith({QueueState? state, String? errorCode, String? errorMessage}) => QueuedOperation(
    operationId: operationId,
    domain: domain,
    recordId: recordId,
    operationType: operationType,
    payload: payload,
    createdAt: createdAt,
    parentId: parentId,
    state: state ?? this.state,
    errorCode: errorCode,
    errorMessage: errorMessage,
  );

  /// Bentuk kiriman untuk POST /api/me/sync/operations.
  Map<String, dynamic> toWire() => {
    'operationId': operationId,
    'domain': domain,
    'recordId': recordId,
    'operationType': operationType,
    'payload': payload,
    'parentId': ?parentId,
  };

  Map<String, dynamic> toJson() => {
    ...toWire(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'state': state.name,
    'errorCode': errorCode,
    'errorMessage': errorMessage,
  };

  factory QueuedOperation.fromJson(Map<String, dynamic> j) => QueuedOperation(
    operationId: j['operationId'] as String,
    domain: j['domain'] as String,
    recordId: j['recordId'] as String,
    operationType: j['operationType'] as String,
    parentId: j['parentId'] as String?,
    payload: (j['payload'] as Map).cast<String, dynamic>(),
    createdAt: DateTime.parse(j['createdAt'] as String),
    state: QueueState.values.asNameMap()[j['state']] ?? QueueState.savedLocal,
    errorCode: j['errorCode'] as String?,
    errorMessage: j['errorMessage'] as String?,
  );

  /// Nama domain yang ramah pembaca.
  String get label => switch (domain) {
    'meal' => 'Makanan',
    'glucose' => 'Glukosa',
    'activity' => 'Aktivitas',
    'medication_intake' => 'Konfirmasi obat',
    'goal_checkin' => 'Check-in tujuan',
    _ => domain,
  };
}

/// Antrean per akun. Kunci memuat id akun sehingga akun lain tidak pernah membaca antrean ini,
/// dan operasi tidak pernah dikirim dengan token akun yang berbeda dari pemiliknya.
class OfflineQueue {
  OfflineQueue(this._store, this.accountId);
  final KeyValueStore _store;
  final String accountId;

  String get _key => 'beokay.queue.$accountId';

  Future<List<QueuedOperation>> load() async {
    try {
      final raw = await _store.read(_key);
      if (raw == null) return const [];
      return (jsonDecode(raw) as List).map((e) => QueuedOperation.fromJson((e as Map).cast<String, dynamic>())).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _save(List<QueuedOperation> ops) =>
      ops.isEmpty ? _store.delete(_key) : _store.write(_key, jsonEncode([for (final o in ops) o.toJson()]));

  Future<void> add(QueuedOperation op) async {
    final ops = await load();
    if (ops.any((o) => o.operationId == op.operationId || (o.recordId == op.recordId && o.domain == op.domain))) return;
    await _save([...ops, op]);
  }

  Future<void> replaceAll(List<QueuedOperation> ops) => _save(ops);

  Future<void> remove(String operationId) async => _save([for (final o in await load()) if (o.operationId != operationId) o]);

  Future<void> clear() => _store.delete(_key);
}
