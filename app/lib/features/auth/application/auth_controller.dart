import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/reminder_scheduler.dart';
import '../../push/application/push_controller.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../data/auth_repository.dart';
import '../data/session_user.dart';

sealed class AuthState {
  const AuthState();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated({this.sessionExpired = false});
  final bool sessionExpired;
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user);
  final SessionUser user;
}

class AuthUnavailable extends AuthState {
  const AuthUnavailable(this.message);
  final String message;
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    api: ref.watch(apiClientProvider),
    tokens: ref.watch(tokenStorageProvider),
  );
});

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    Future.microtask(restore);
    return const AuthLoading();
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> restore() async {
    state = const AuthLoading();
    try {
      final user = await _repo.restore();
      state = user == null
          ? const AuthUnauthenticated()
          : AuthAuthenticated(user);
    } on ApiException catch (error) {
      state = AuthUnavailable(error.message);
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    final user = await _repo.signIn(email: email, password: password);
    state = AuthAuthenticated(user);
  }

  /// Notifikasi pengingat tidak boleh tersisa setelah keluar akun atau sesi habis.
  void _cancelReminders() => unawaited(
    ref.read(reminderSchedulerProvider).cancelAll().catchError((_) {}),
  );

  Future<void> signOut() async {
    // Selama sesi masih berlaku: cabut perangkat push agar akun berikutnya tidak menerima pengingat akun ini (best effort).
    try {
      await ref.read(pushControllerProvider.notifier).disable();
    } catch (_) {}
    await _repo.signOut();
    _cancelReminders();
    state = const AuthUnauthenticated();
  }

  void sessionExpired() {
    if (state is! AuthAuthenticated) return;
    _repo.clearLocalSession();
    _cancelReminders();
    state = const AuthUnauthenticated(sessionExpired: true);
  }

  void updateDisplayName(String name) {
    final current = state;
    if (current is! AuthAuthenticated) return;
    final user = current.user;
    state = AuthAuthenticated(
      SessionUser(
        id: user.id,
        email: user.email,
        name: name,
        emailVerified: user.emailVerified,
      ),
    );
  }
}
