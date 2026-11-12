import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/offline/sync_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/beokay_logo.dart';
import '../../core/widgets/pill_button.dart';
import '../../core/widgets/settings_group.dart';
import '../auth/application/auth_controller.dart';

abstract interface class DeviceAuthenticator {
  Future<bool> available();
  Future<bool> authenticate(String reason);
}

class LocalDeviceAuthenticator implements DeviceAuthenticator {
  final _auth = LocalAuthentication();
  @override
  Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}

final deviceAuthenticatorProvider = Provider<DeviceAuthenticator>(
  (ref) => LocalDeviceAuthenticator(),
);

class AppLockState {
  const AppLockState({
    this.enabled = false,
    this.locked = false,
    this.loaded = false,
  });
  final bool enabled, locked, loaded;
  AppLockState copyWith({bool? enabled, bool? locked, bool? loaded}) =>
      AppLockState(
        enabled: enabled ?? this.enabled,
        locked: locked ?? this.locked,
        loaded: loaded ?? this.loaded,
      );
}

class _Lifecycle with WidgetsBindingObserver {
  _Lifecycle(this.onChange);
  final void Function(AppLifecycleState) onChange;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => onChange(state);
}

class AppLockController extends Notifier<AppLockState> {
  static const graceSeconds = 60;
  DateTime? _backgroundAt;

  String? get _key {
    final auth = ref.read(authControllerProvider);
    return auth is AuthAuthenticated ? 'beokay.applock.${auth.user.id}' : null;
  }

  @override
  AppLockState build() {
    ref.watch(authControllerProvider);
    final observer = _Lifecycle(_onLifecycle);
    WidgetsBinding.instance.addObserver(observer);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
    _load();
    return const AppLockState();
  }

  Future<void> _load() async {
    final key = _key;
    if (key == null) return;
    final on = await ref.read(keyValueStoreProvider).read(key) == 'on';
    if (ref.mounted) {
      state = AppLockState(enabled: on, locked: on, loaded: true);
    }
  }

  void _onLifecycle(AppLifecycleState s) {
    if (!state.enabled) return;
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      _backgroundAt ??= DateTime.now();
    } else if (s == AppLifecycleState.resumed) {
      final away = _backgroundAt == null
          ? 0
          : DateTime.now().difference(_backgroundAt!).inSeconds;
      _backgroundAt = null;
      if (away >= graceSeconds) state = state.copyWith(locked: true);
    }
  }

  Future<bool> unlock() async {
    final ok = await ref
        .read(deviceAuthenticatorProvider)
        .authenticate('Buka beOkay');
    if (ok) state = state.copyWith(locked: false);
    return ok;
  }

  Future<bool> setEnabled(bool on) async {
    final key = _key;
    if (key == null) return false;
    final auth = ref.read(deviceAuthenticatorProvider);
    if (on && !await auth.available()) return false;
    if (!await auth.authenticate(
      on ? 'Nyalakan kunci aplikasi' : 'Matikan kunci aplikasi',
    )) {
      return false;
    }
    final store = ref.read(keyValueStoreProvider);
    on ? await store.write(key, 'on') : await store.delete(key);
    state = state.copyWith(enabled: on, locked: false, loaded: true);
    return true;
  }

  Future<bool> confirmSensitive(String reason) async {
    if (!state.enabled) return true;
    return ref.read(deviceAuthenticatorProvider).authenticate(reason);
  }
}

final appLockProvider = NotifierProvider<AppLockController, AppLockState>(
  AppLockController.new,
);

class AppLockGate extends ConsumerWidget {
  const AppLockGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    if (!lock.enabled || !lock.locked) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(child: child),
        Positioned.fill(
          child: Material(
            color: AppColors.background,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const BeOkayLogo(height: 40),
                    const SizedBox(height: AppSpacing.lg),
                    Semantics(
                      header: true,
                      child: Text(
                        'beOkay terkunci',
                        style: AppTypography.heading,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Buka dengan sidik jari, wajah, atau PIN perangkatmu.',
                      style: AppTypography.secondary,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    PillButton(
                      label: 'Buka kunci',
                      icon: Icons.lock_open_rounded,
                      onPressed: () =>
                          ref.read(appLockProvider.notifier).unlock(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class AppLockRow extends ConsumerWidget {
  const AppLockRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    return SettingsRow(
      icon: Icons.fingerprint,
      title: 'Kunci aplikasi',
      subtitle:
          'Minta sidik jari, wajah, atau PIN saat membuka beOkay dan sebelum ekspor atau hapus akun',
      trailing: Switch(
        value: lock.enabled,
        onChanged: (v) async {
          final messenger = ScaffoldMessenger.of(context);
          final ok = await ref.read(appLockProvider.notifier).setEnabled(v);
          if (!ok) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text(
                  'Kunci perangkat belum tersedia atau verifikasi dibatalkan.',
                ),
              ),
            );
          }
        },
      ),
    );
  }
}
