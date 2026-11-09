import '../ids/record_id.dart';
import '../offline/offline_queue.dart';
import 'api_client.dart';
import 'api_exception.dart';
import '../storage/token_storage.dart';

/// Dilempar setelah permintaan buat-baru gagal karena jaringan dan operasi disimpan di antrean lokal.
class QueuedOffline implements Exception {
  const QueuedOffline(this.operationId);
  final String operationId;
}

/// Menandai penulisan yang boleh diantrekan saat offline (hanya pembuatan catatan baru).
typedef QueueSpec = ({String domain, String recordId, String? parentId});

abstract class AccountScopedRepository {
  AccountScopedRepository(this.api, {required this.isCurrentAccount, this.enqueueOffline});
  final ApiClient api;
  final bool Function() isCurrentAccount;
  final Future<void> Function(QueuedOperation op)? enqueueOffline;

  Future<ApiResponse> write(
    String method,
    String path,
    Map<String, dynamic> body, {
    QueueSpec? queue,
  }) async {
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
    try {
      return await client.send(method, path, body: body);
    } on ApiException catch (e) {
      if (e.isNetwork && queue != null && enqueueOffline != null && isCurrentAccount()) {
        final opId = newRecordId();
        await enqueueOffline!(
          QueuedOperation(
            operationId: opId,
            domain: queue.domain,
            recordId: queue.recordId,
            parentId: queue.parentId,
            operationType: 'create',
            payload: {...body}..remove('id'),
            createdAt: DateTime.now(),
          ),
        );
        throw QueuedOffline(opId);
      }
      rethrow;
    }
  }
}
