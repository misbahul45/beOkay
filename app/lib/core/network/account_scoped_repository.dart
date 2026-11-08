import 'api_client.dart';
import 'api_exception.dart';
import '../storage/token_storage.dart';

abstract class AccountScopedRepository {
  AccountScopedRepository(this.api, {required this.isCurrentAccount});
  final ApiClient api;
  final bool Function() isCurrentAccount;

  Future<ApiResponse> write(
    String method,
    String path,
    Map<String, dynamic> body,
  ) async {
    final token = await api.tokens.read();
    if (token == null || !isCurrentAccount()) {
      throw const ApiException(
        status: 401,
        code: 'ACCOUNT_CHANGED',
        message: 'Akun berubah. Buka kembali formulir.',
      );
    }
    final captured = MemoryTokenStorage();
    await captured.write(token);
    final client = ApiClient(
      client: api.client,
      tokens: captured,
      baseUrl: api.baseUrl,
      onUnauthorized: () {
        if (isCurrentAccount()) api.onUnauthorized?.call();
      },
    );
    return client.send(method, path, body: body);
  }
}
