import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/token_storage.dart';
import 'session_user.dart';

class AuthRepository {
  AuthRepository({required this.api, required this.tokens});

  final ApiClient api;
  final TokenStorage tokens;

  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    await api.post(
      '/api/auth/sign-up/email',
      body: {'name': name, 'email': email, 'password': password},
      authenticated: false,
    );
  }

  Future<SessionUser> signIn({
    required String email,
    required String password,
  }) async {
    final response = await api.post(
      '/api/auth/sign-in/email',
      body: {'email': email, 'password': password},
      authenticated: false,
    );
    final token = response.headers['set-auth-token'];
    if (token == null || token.isEmpty) {
      throw const ApiException(
        status: 500,
        code: 'MISSING_SESSION_TOKEN',
        message: 'Sesi tidak bisa dibuat. Coba lagi.',
      );
    }
    await tokens.write(token);
    return SessionUser.fromJson(
      response.object['user'] as Map<String, dynamic>,
    );
  }

  Future<SessionUser?> restore() async {
    final token = await tokens.read();
    if (token == null) return null;
    try {
      final response = await api.get('/api/auth/get-session');
      final user = response.object['user'];
      if (user is Map<String, dynamic>) return SessionUser.fromJson(user);
    } on ApiException catch (error) {
      if (error.isNetwork || error.status >= 500) rethrow;
    }
    await tokens.clear();
    return null;
  }

  Future<void> signOut() async {
    await api.post('/api/auth/sign-out').then<void>((_) {}, onError: (_) {});
    await tokens.clear();
  }

  Future<void> clearLocalSession() => tokens.clear();

  Future<void> resendVerification(String email) async {
    await api.post(
      '/api/auth/send-verification-email',
      body: {'email': email},
      authenticated: false,
    );
  }

  Future<void> requestPasswordReset(String email) async {
    await api.post(
      '/api/auth/request-password-reset',
      body: {'email': email},
      authenticated: false,
    );
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await api.post(
      '/api/auth/change-password',
      body: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
        'revokeOtherSessions': true,
      },
    );
  }

  Future<List<DeviceSession>> listSessions() async {
    final current = await tokens.read();
    final response = await api.get('/api/auth/list-sessions');
    return response.list.whereType<Map<String, dynamic>>().map((item) {
      final token = item['token'] as String? ?? '';
      return DeviceSession(
        id: item['id'] as String? ?? token,
        token: token,
        userAgent: item['userAgent'] as String? ?? '',
        ipAddress: item['ipAddress'] as String? ?? '',
        createdAt:
            DateTime.tryParse(item['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        isCurrent: token == current,
      );
    }).toList();
  }

  Future<void> revokeOtherSessions() async {
    await api.post('/api/auth/revoke-other-sessions');
  }
}
