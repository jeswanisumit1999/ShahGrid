/// Maps backend error codes to typed exceptions for clean error handling.
class AppException implements Exception {
  const AppException({required this.code, required this.message, this.statusCode});

  final String code;
  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isCreditLimitExceeded => code == 'CREDIT_LIMIT_EXCEEDED';
  bool get isInsufficientStock => code == 'INSUFFICIENT_STOCK';

  @override
  String toString() => 'AppException($code): $message';

  factory AppException.fromJson(Map<String, dynamic> json, {int? statusCode}) {
    final error = json['error'] as Map<String, dynamic>? ?? {};
    return AppException(
      code: error['code'] as String? ?? 'UNKNOWN',
      message: error['message'] as String? ?? 'An unexpected error occurred',
      statusCode: statusCode,
    );
  }

  factory AppException.network(String message) =>
      AppException(code: 'NETWORK_ERROR', message: message);

  factory AppException.unknown() =>
      const AppException(code: 'UNKNOWN', message: 'An unexpected error occurred');
}
