class ApiException implements Exception {
  const ApiException({
    required this.status,
    required this.code,
    required this.message,
    this.details,
  });

  final int status;
  final String code;
  final String message;
  final Map<String, dynamic>? details;

  bool get isUnauthorized => status == 401;
  bool get isNetwork => code == networkCode;
  bool get isRateLimited => status == 429;

  static const networkCode = 'NETWORK_ERROR';

  @override
  String toString() => 'ApiException($status, $code)';
}
