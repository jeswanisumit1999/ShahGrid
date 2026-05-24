import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/api_constants.dart';
import '../errors/app_exception.dart';

const _storage = FlutterSecureStorage();
const _accessTokenKey = 'access_token';
const _refreshTokenKey = 'refresh_token';

/// Persists and retrieves JWT tokens from secure storage.
class TokenStorage {
  static Future<String?> getAccessToken() => _storage.read(key: _accessTokenKey);
  static Future<String?> getRefreshToken() => _storage.read(key: _refreshTokenKey);
  static Future<void> saveTokens({required String access, String? refresh}) async {
    await _storage.write(key: _accessTokenKey, value: access);
    if (refresh != null) await _storage.write(key: _refreshTokenKey, value: refresh);
  }
  static Future<void> clearTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }
}

/// Dio instance with auth interceptor: attaches Bearer token and auto-refreshes on 401.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: ApiConstants.baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
  ));

  dio.interceptors.add(_AuthInterceptor(dio));
  return dio;
});

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._dio);
  final Dio _dio;
  bool _isRefreshing = false;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await TokenStorage.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;
      try {
        final refreshToken = await TokenStorage.getRefreshToken();
        if (refreshToken == null) {
          await TokenStorage.clearTokens();
          handler.next(err);
          return;
        }

        // Exchange refresh token for a new access token
        final response = await _dio.post(
          ApiConstants.refresh,
          data: {'refreshToken': refreshToken},
          options: Options(headers: {'Authorization': null}),
        );

        final newToken = response.data['data']['accessToken'] as String;
        await TokenStorage.saveTokens(access: newToken);

        // Retry the original request with the new token
        final retryOptions = err.requestOptions;
        retryOptions.headers['Authorization'] = 'Bearer $newToken';
        final retryResponse = await _dio.fetch(retryOptions);
        handler.resolve(retryResponse);
      } catch (_) {
        await TokenStorage.clearTokens();
        handler.next(err);
      } finally {
        _isRefreshing = false;
      }
      return;
    }

    // Convert Dio errors into AppException
    final statusCode = err.response?.statusCode;
    final data = err.response?.data;
    if (data is Map<String, dynamic>) {
      handler.reject(
        DioException(
          requestOptions: err.requestOptions,
          error: AppException.fromJson(data, statusCode: statusCode),
          response: err.response,
          type: err.type,
        ),
      );
    } else {
      handler.next(err);
    }
  }
}

/// Safely unwrap a successful API response's `data` field.
T unwrap<T>(Response response) {
  final body = response.data as Map<String, dynamic>;
  return body['data'] as T;
}

/// Extract the [AppException] from any error, preserving the message where possible.
AppException parseError(Object err) {
  if (err is DioException) {
    if (err.error is AppException) return err.error as AppException;
    return const AppException(code: 'NETWORK_ERROR', message: 'Network error');
  }
  if (err is AppException) return err;
  return AppException.unknown();
}

/// Returns a user-friendly message for any thrown error — never exposes raw exception text.
String friendlyError(Object err) {
  final ex = parseError(err);
  switch (ex.code) {
    case 'CREDIT_LIMIT_EXCEEDED':     return 'This order exceeds the retailer\'s credit limit';
    case 'INSUFFICIENT_STOCK':        return 'Insufficient stock for one or more products';
    case 'PAID_AMOUNT_EXCEEDS_TOTAL': return 'Amount paid cannot exceed the order total';
    case 'UNAUTHORIZED':              return 'Please sign in to continue';
    case 'FORBIDDEN':                 return 'You don\'t have permission to do this';
    case 'NOT_FOUND':                 return 'The requested item was not found';
    case 'CONFLICT':                  return 'This record already exists';
    case 'DUPLICATE_PAYMENT':         return 'This payment may already have been recorded';
    case 'SYSTEM_ROLE':               return 'System roles cannot be modified';
    case 'ROLE_IN_USE':               return 'This role is currently assigned to users';
    case 'INVALID_STATUS_TRANSITION': return 'This action cannot be performed at this stage';
    case 'INVALID_QUANTITY':          return 'Please check the quantities entered';
    case 'INVALID_ITEMS':             return 'One or more items are invalid';
    case 'SPLIT_TOO_MANY':            return 'Too many shipments would result from this split';
    case 'INVALID_SPLIT_STATUS':      return 'This shipment cannot be split at this stage';
    case 'NETWORK_ERROR':             return 'Connection error — please check your internet and try again';
    case 'INTERNAL_ERROR':            return 'Something went wrong. Please try again later';
    case 'VALIDATION_ERROR':          return ex.message;
    default:                          return 'Something went wrong. Please try again';
  }
}
