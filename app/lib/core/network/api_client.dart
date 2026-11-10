import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';

class ApiResponse {
  const ApiResponse({
    required this.status,
    required this.headers,
    required this.json,
  });

  final int status;
  final Map<String, String> headers;
  final Object? json;

  Map<String, dynamic> get object =>
      json is Map<String, dynamic> ? json! as Map<String, dynamic> : const {};
  List<dynamic> get list => json is List ? json! as List : const [];
}

class ApiClient {
  ApiClient({
    required this.client,
    required this.tokens,
    String? baseUrl,
    this.onUnauthorized,
  }) : baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client client;
  final TokenStorage tokens;
  final String baseUrl;
  final void Function()? onUnauthorized;

  Future<ApiResponse> get(String path, {bool authenticated = true}) =>
      send('GET', path, authenticated: authenticated);

  Future<ApiResponse> post(
    String path, {
    Object? body,
    bool authenticated = true,
  }) => send(
    'POST',
    path,
    body: body ?? const <String, dynamic>{},
    authenticated: authenticated,
  );

  Future<ApiResponse> patch(String path, {required Object body}) =>
      send('PATCH', path, body: body);

  Future<ApiResponse> put(String path, {required Object body}) =>
      send('PUT', path, body: body);

  /// Kirim berkas biner (mis. foto) dengan batas waktu lebih longgar; balasan tetap JSON.
  Future<ApiResponse> postBytes(
    String path,
    List<int> bytes, {
    required String contentType,
    Duration timeout = const Duration(seconds: 40),
  }) => send(
    'POST',
    path,
    bytes: bytes,
    contentType: contentType,
    timeout: timeout,
  );

  Future<ApiResponse> send(
    String method,
    String path, {
    Object? body,
    List<int>? bytes,
    String? contentType,
    Duration? timeout,
    bool authenticated = true,
  }) async {
    final headers = <String, String>{'Accept': 'application/json'};
    String? token;
    if (authenticated) {
      token = await tokens.read();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    if (body != null) headers['Content-Type'] = 'application/json';
    if (bytes != null) {
      headers['Content-Type'] = contentType ?? 'application/octet-stream';
    }

    final request = http.Request(method, Uri.parse('$baseUrl$path'));
    request.headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    if (bytes != null) request.bodyBytes = bytes;

    http.Response response;
    try {
      response = await http.Response.fromStream(
        await client.send(request).timeout(timeout ?? AppConfig.requestTimeout),
      );
    } on TimeoutException {
      throw const ApiException(
        status: 0,
        code: ApiException.networkCode,
        message: 'Server tidak merespons. Coba lagi.',
      );
    } on http.ClientException {
      throw const ApiException(
        status: 0,
        code: ApiException.networkCode,
        message: 'Tidak bisa terhubung. Periksa koneksimu.',
      );
    }

    Object? decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        decoded = null;
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return ApiResponse(
        status: response.statusCode,
        headers: response.headers,
        json: decoded,
      );
    }

    final error = _parseError(response.statusCode, decoded);
    if (error.isUnauthorized && token != null) onUnauthorized?.call();
    throw error;
  }

  ApiException _parseError(int status, Object? decoded) {
    if (decoded is Map<String, dynamic>) {
      final nested = decoded['error'];
      if (nested is Map<String, dynamic>) {
        return ApiException(
          status: status,
          code: nested['code'] as String? ?? 'UNKNOWN_ERROR',
          message: nested['message'] as String? ?? 'Terjadi kendala.',
          details: nested['details'] is Map<String, dynamic>
              ? nested['details'] as Map<String, dynamic>
              : null,
        );
      }
      return ApiException(
        status: status,
        code: decoded['code'] as String? ?? 'UNKNOWN_ERROR',
        message: decoded['message'] as String? ?? 'Terjadi kendala.',
      );
    }
    return ApiException(
      status: status,
      code: 'UNKNOWN_ERROR',
      message: 'Terjadi kendala. Coba lagi nanti.',
    );
  }
}
