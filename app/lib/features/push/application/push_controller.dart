import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/offline/offline_queue.dart';
import '../../../core/offline/sync_controller.dart';
import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../data/push_client.dart';
import '../data/push_repository.dart';

final pushRepositoryProvider = Provider<PushRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  final id = auth is AuthAuthenticated ? auth.user.id : null;
  return PushRepository(
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

enum PushStatus { unavailable, off, on }

class PushState {
  const PushState(this.status, {this.message});
  final PushStatus status;
  final String? message;
}

/// Push opsional per akun dan per perangkat. Bila aktif, server mengirim pengingat lewat FCM dan perangkat TIDAK
/// menjadwalkan notifikasi lokal (agar tidak ganda). Status disimpan terenkripsi di perangkat bersama id perangkat server.
class PushController extends Notifier<PushState> {
  String get _key =>
      'beokay.push.${(ref.read(authControllerProvider) as AuthAuthenticated).user.id}';
  StreamSubscription<String>? _refresh;

  @override
  PushState build() {
    final auth = ref.watch(authControllerProvider);
    ref.onDispose(() => _refresh?.cancel());
    if (auth is AuthAuthenticated) unawaited(_load());
    return const PushState(PushStatus.unavailable);
  }

  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  Future<void> _load() async {
    final client = ref.read(pushClientProvider);
    if (!await client.available()) {
      if (ref.mounted) state = const PushState(PushStatus.unavailable);
      return;
    }
    final saved = await _store.read(_key);
    if (!ref.mounted) return;
    state = PushState(saved == null ? PushStatus.off : PushStatus.on);
    if (saved != null) {
      _refresh?.cancel();
      _refresh = client.onTokenRefresh.listen((t) => unawaited(_register(t)));
    }
  }

  Future<void> _register(String token) async {
    final device = await ref.read(pushRepositoryProvider).register(token);
    await _store.write(_key, device.id);
  }

  /// Mengaktifkan push: izin → token → daftar ke server. Gagal di langkah mana pun = tetap mati dengan pesan.
  Future<void> enable() async {
    final client = ref.read(pushClientProvider);
    if (!await client.available()) {
      state = const PushState(PushStatus.unavailable);
      return;
    }
    if (!await client.requestPermission()) {
      state = const PushState(
        PushStatus.off,
        message: 'Notifikasi belum diizinkan di pengaturan perangkat.',
      );
      return;
    }
    try {
      final token = await client.token();
      if (token == null) {
        state = const PushState(
          PushStatus.off,
          message: 'Token notifikasi belum tersedia. Coba lagi.',
        );
        return;
      }
      await _register(token);
      _refresh?.cancel();
      _refresh = client.onTokenRefresh.listen((t) => unawaited(_register(t)));
      state = const PushState(PushStatus.on);
    } catch (_) {
      state = const PushState(
        PushStatus.off,
        message:
            'Tidak dapat mendaftarkan perangkat. Periksa koneksi lalu coba lagi.',
      );
    }
  }

  /// Mematikan push: server menghapus token, token perangkat dicabut, dan jadwal lokal dipakai kembali.
  Future<void> disable() async {
    final id = await _store.read(_key);
    try {
      if (id != null) await ref.read(pushRepositoryProvider).unregister(id);
    } catch (_) {
      // gagal menghubungi server: token dicabut di perangkat tetap membuatnya tak berlaku
    }
    try {
      await ref.read(pushClientProvider).deleteToken();
    } catch (_) {}
    await _store.delete(_key);
    _refresh?.cancel();
    if (ref.mounted) state = const PushState(PushStatus.off);
  }

  /// True bila perangkat ini sudah terdaftar untuk push (dipakai penjadwal lokal untuk menghindari notifikasi ganda).
  /// Bila penyimpanan gagal dibaca, dianggap belum terdaftar: pengingat lokal tetap jalan (lebih baik ganda daripada hilang).
  Future<bool> registeredHere() async {
    try {
      return (await _store.read(_key)) != null;
    } catch (_) {
      return false;
    }
  }
}

final pushControllerProvider = NotifierProvider<PushController, PushState>(
  PushController.new,
);
