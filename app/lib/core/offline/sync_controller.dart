import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../network/api_exception.dart';
import '../providers.dart';
import 'offline_queue.dart';

final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => SecureKeyValueStore(),
);

/// Antrean milik akun yang sedang masuk; null bila belum masuk.
final offlineQueueProvider = Provider<OfflineQueue?>((ref) {
  final auth = ref.watch(authControllerProvider);
  if (auth is! AuthAuthenticated) return null;
  return OfflineQueue(ref.watch(keyValueStoreProvider), auth.user.id);
});

class SyncSnapshot {
  const SyncSnapshot({
    this.items = const [],
    this.running = false,
    this.blockedByConsent = false,
    this.offline = false,
  });
  final List<QueuedOperation> items;
  final bool running;
  final bool blockedByConsent;
  final bool offline;

  int get pending => items
      .where(
        (o) =>
            o.state == QueueState.savedLocal ||
            o.state == QueueState.syncFailed,
      )
      .length;
  int get needsAttention => items
      .where(
        (o) =>
            o.state == QueueState.conflict || o.state == QueueState.needsReview,
      )
      .length;
}

class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this.onResume);
  final void Function() onResume;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

class SyncController extends Notifier<SyncSnapshot> {
  bool _flushing = false;

  @override
  SyncSnapshot build() {
    final queue = ref.watch(offlineQueueProvider);
    if (queue != null) unawaited(_load(queue));
    // Pengiriman berkala dan saat aplikasi dibuka kembali; hidup selama akun masuk, tidak terikat layar tertentu.
    final timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    final observer = _ResumeObserver(_tick);
    WidgetsBinding.instance.addObserver(observer);
    ref.onDispose(() {
      timer.cancel();
      WidgetsBinding.instance.removeObserver(observer);
    });
    return const SyncSnapshot();
  }

  void _tick() {
    if (ref.mounted && state.pending > 0) unawaited(flush());
  }

  Future<void> _load(OfflineQueue queue) async {
    final items = await queue.load();
    if (!ref.mounted) return;
    state = SyncSnapshot(items: items);
    if (items.any(
      (o) =>
          o.state == QueueState.savedLocal || o.state == QueueState.syncFailed,
    )) {
      unawaited(flush());
    }
  }

  /// Dipanggil repositori saat jaringan gagal. Menyimpan lokal, lalu mencoba kirim di latar.
  Future<void> enqueue(QueuedOperation op) async {
    final queue = ref.read(offlineQueueProvider);
    if (queue == null) return;
    await queue.add(op);
    if (ref.mounted) state = SyncSnapshot(items: await queue.load());
  }

  Future<void> flush() async {
    final queue = ref.read(offlineQueueProvider);
    if (queue == null || _flushing) return;
    final accountId = queue.accountId;
    _flushing = true;
    try {
      var items = await queue.load();
      final todo = items
          .where(
            (o) =>
                o.state == QueueState.savedLocal ||
                o.state == QueueState.syncFailed,
          )
          .toList();
      if (todo.isEmpty) return;
      state = SyncSnapshot(items: items, running: true);
      final api = ref.read(apiClientProvider);
      try {
        for (var i = 0; i < todo.length; i += 50) {
          final batch = todo.sublist(
            i,
            i + 50 > todo.length ? todo.length : i + 50,
          );
          final res = await api.post(
            '/api/me/sync/operations',
            body: {
              'operations': [for (final o in batch) o.toWire()],
            },
          );
          // Akun berganti saat permintaan berjalan: jangan menyentuh antrean akun lain.
          final auth = ref.read(authControllerProvider);
          if (!ref.mounted ||
              auth is! AuthAuthenticated ||
              auth.user.id != accountId) {
            return;
          }
          final results = {
            for (final r in (res.object['items'] as List))
              (r as Map)['operationId'] as String: r.cast<String, dynamic>(),
          };
          items = await queue.load();
          final next = <QueuedOperation>[];
          for (final o in items) {
            final r = results[o.operationId];
            if (r == null) {
              next.add(o);
              continue;
            }
            switch (r['status']) {
              case 'SYNCED':
                break; // selesai: hapus dari antrean
              case 'CONFLICT':
                next.add(
                  o.copyWith(
                    state: QueueState.conflict,
                    errorCode: (r['error'] as Map?)?['code'] as String?,
                    errorMessage: (r['error'] as Map?)?['message'] as String?,
                  ),
                );
              case 'NEEDS_REVIEW':
                next.add(
                  o.copyWith(
                    state: QueueState.needsReview,
                    errorCode: (r['error'] as Map?)?['code'] as String?,
                    errorMessage: (r['error'] as Map?)?['message'] as String?,
                  ),
                );
              default:
                next.add(o.copyWith(state: QueueState.syncFailed));
            }
          }
          await queue.replaceAll(next);
        }
        if (ref.mounted) state = SyncSnapshot(items: await queue.load());
      } on ApiException catch (e) {
        if (!ref.mounted) return;
        final cur = await queue.load();
        state = SyncSnapshot(
          items: cur,
          offline: e.isNetwork,
          blockedByConsent: e.code == 'CONSENT_REQUIRED',
        );
      }
    } finally {
      _flushing = false;
    }
  }

  /// Membuang satu operasi atas keputusan pengguna (konflik / perlu ditinjau).
  Future<void> discard(String operationId) async {
    final queue = ref.read(offlineQueueProvider);
    if (queue == null) return;
    await queue.remove(operationId);
    if (ref.mounted) state = SyncSnapshot(items: await queue.load());
  }

  /// Mengembalikan operasi yang gagal sementara agar dicoba lagi.
  Future<void> retry(String operationId) async {
    final queue = ref.read(offlineQueueProvider);
    if (queue == null) return;
    final items = await queue.load();
    await queue.replaceAll([
      for (final o in items)
        o.operationId == operationId
            ? o.copyWith(state: QueueState.savedLocal)
            : o,
    ]);
    await flush();
  }

  /// Dipanggil saat persetujuan pemrosesan data kesehatan ditarik: data lokal yang belum terkirim dihapus.
  Future<void> clearForConsentWithdrawal() async {
    await ref.read(offlineQueueProvider)?.clear();
    if (ref.mounted) state = const SyncSnapshot();
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncSnapshot>(
  SyncController.new,
);
