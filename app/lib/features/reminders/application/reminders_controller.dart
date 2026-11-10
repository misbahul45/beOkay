import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/notifications/reminder_scheduler.dart';
import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../../consent/application/consent_controller.dart';
import '../../preferences/application/preferences_controller.dart';
import '../../push/application/push_controller.dart';
import '../data/reminders_repository.dart';

final remindersRepositoryProvider = Provider<RemindersRepository>((ref) {
  final auth = ref.watch(authControllerProvider);
  final id = auth is AuthAuthenticated ? auth.user.id : null;
  return RemindersRepository(
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

final remindersProvider = FutureProvider.autoDispose<ReminderRules>((
  ref,
) async {
  await Future.wait([
    ref.watch(consentControllerProvider.future),
    ref.watch(preferencesControllerProvider.future),
  ]);
  return ref.watch(remindersRepositoryProvider).list();
});

/// Menyelaraskan notifikasi lokal dengan aturan di server: saat masuk, saat aplikasi dibuka kembali, dan
/// setelah perubahan. Keluar akun atau consent hilang → semua notifikasi dibatalkan, tidak ada yang tertinggal.
class ReminderSyncController extends Notifier<DateTime?> {
  bool _running = false;
  _Observer? _observer;

  @override
  DateTime? build() {
    final auth = ref.watch(authControllerProvider);
    _observer ??= _Observer(() => unawaited(sync()));
    WidgetsBinding.instance.addObserver(_observer!);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(_observer!));
    if (auth is AuthAuthenticated) {
      unawaited(sync());
    } else {
      unawaited(
        ref.read(reminderSchedulerProvider).cancelAll().catchError((_) {}),
      );
    }
    return null;
  }

  Future<void> sync() async {
    if (_running || ref.read(authControllerProvider) is! AuthAuthenticated) {
      return;
    }
    _running = true;
    try {
      // Push aktif di perangkat ini: server yang mengirim; jadwal lokal dikosongkan agar tidak ada notifikasi ganda.
      if (await ref.read(pushControllerProvider.notifier).registeredHere()) {
        await ref.read(reminderSchedulerProvider).cancelAll();
        if (ref.mounted) state = DateTime.now();
        return;
      }
      final items = await ref.read(remindersRepositoryProvider).upcoming();
      await ref.read(reminderSchedulerProvider).replaceAll(items);
      if (ref.mounted) state = DateTime.now();
    } on ApiException catch (e) {
      // Consent ditarik atau sesi habis: jangan biarkan notifikasi lama tetap muncul.
      if (e.status == 401 || e.status == 403) {
        await ref
            .read(reminderSchedulerProvider)
            .cancelAll()
            .catchError((_) {});
      }
      // Gangguan jaringan: pertahankan jadwal terakhir yang sudah ada di perangkat.
    } catch (_) {
      // Kegagalan plugin tidak boleh menjatuhkan aplikasi.
    } finally {
      _running = false;
    }
  }
}

class _Observer with WidgetsBindingObserver {
  _Observer(this.onResume);
  final void Function() onResume;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

final reminderSyncProvider =
    NotifierProvider<ReminderSyncController, DateTime?>(
      ReminderSyncController.new,
    );
