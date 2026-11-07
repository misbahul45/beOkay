import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  return AuthRepository(api: ref.watch(apiClientProvider), tokens: ref.watch(tokenStorageProvider));
});

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

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
      state = user == null ? const AuthUnauthenticated() : AuthAuthenticated(user);
    } on ApiException catch (error) {
      state = AuthUnavailable(error.message);
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    final user = await _repo.signIn(email: email, password: password);
    state = AuthAuthenticated(user);
  }

  Future<void> signOut() async {
    await _repo.signOut();
    state = const AuthUnauthenticated();
  }

  void sessionExpired() {
    if (state is! AuthAuthenticated) return;
    _repo.clearLocalSession();
    state = const AuthUnauthenticated(sessionExpired: true);
  }

  void updateDisplayName(String name) {
    final current = state;
    if (current is! AuthAuthenticated) return;
    final user = current.user;
    state = AuthAuthenticated(SessionUser(id: user.id, email: user.email, name: name, emailVerified: user.emailVerified));
  }
}
