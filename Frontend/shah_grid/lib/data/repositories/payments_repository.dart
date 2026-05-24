import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/dio_client.dart';
import '../models/payment_model.dart';
import '../models/user_model.dart';

final paymentsRepositoryProvider = Provider<PaymentsRepository>((ref) {
  return PaymentsRepository(ref.read(dioProvider));
});

class PaymentsRepository {
  PaymentsRepository(this._dio);
  final Dio _dio;

  Future<PaginatedResult<PaymentModel>> list({
    String? cursor,
    int limit = 20,
    String? orderId,
    String? retailerId,
    String? search,
  }) async {
    final response = await _dio.get(ApiConstants.payments, queryParameters: {
      if (cursor != null) 'cursor': cursor,
      'limit': limit,
      if (orderId != null) 'orderId': orderId,
      if (retailerId != null) 'retailerId': retailerId,
      if (search != null && search.isNotEmpty) 'search': search,
    });
    final body = response.data as Map<String, dynamic>;
    final pagination = body['pagination'] as Map<String, dynamic>? ?? {};
    return PaginatedResult(
      items: (body['data'] as List)
          .map((e) => PaymentModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMore: pagination['hasMore'] as bool? ?? false,
      nextCursor: pagination['nextCursor'] as String?,
    );
  }

  Future<PaymentModel> record({
    required String retailerId,
    required double amount,
    required String paymentDate,
    required String method,
    String? companyId,
    String? referenceNo,
    String? notes,
    String? idempotencyKey,
  }) async {
    final response = await _dio.post(ApiConstants.payments, data: {
      'retailerId': retailerId,
      'amount': amount,
      'paymentDate': paymentDate,
      'method': method,
      if (companyId != null) 'companyId': companyId,
      if (referenceNo != null && referenceNo.isNotEmpty) 'referenceNo': referenceNo,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
    });
    return PaymentModel.fromJson(unwrap<Map<String, dynamic>>(response));
  }
}
