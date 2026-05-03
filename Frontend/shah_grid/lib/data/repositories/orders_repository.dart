import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/dio_client.dart';
import '../models/order_model.dart';
import '../models/user_model.dart';

final ordersRepositoryProvider = Provider<OrdersRepository>((ref) {
  return OrdersRepository(ref.read(dioProvider));
});

class OrdersRepository {
  OrdersRepository(this._dio);
  final Dio _dio;

  Future<PaginatedResult<OrderModel>> list({
    String? cursor,
    int limit = 20,
    String? retailerId,
    String? salesOfficerId,
  }) async {
    final response = await _dio.get(ApiConstants.orders, queryParameters: {
      if (cursor != null) 'cursor': cursor,
      'limit': limit,
      if (retailerId != null) 'retailerId': retailerId,
      if (salesOfficerId != null) 'salesOfficerId': salesOfficerId,
    });
    final body = response.data as Map<String, dynamic>;
    final pagination = body['pagination'] as Map<String, dynamic>? ?? {};
    return PaginatedResult(
      items: (body['data'] as List)
          .map((e) => OrderModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMore: pagination['hasMore'] as bool? ?? false,
      nextCursor: pagination['nextCursor'] as String?,
    );
  }

  Future<OrderModel> getById(String id) async {
    final response = await _dio.get(ApiConstants.orderById(id));
    return OrderModel.fromJson(unwrap<Map<String, dynamic>>(response));
  }

  Future<Uint8List> downloadChallan(String id) async {
    final response = await _dio.get<List<int>>(
      ApiConstants.orderChallan(id),
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data!);
  }

  Future<OrderModel> create({
    required String retailerId,
    required String salesOfficerId,
    required List<Map<String, dynamic>> items,
    bool isDirectSale = false,
    String? overrideCompanyId,
    String? notes,
  }) async {
    final response = await _dio.post(ApiConstants.orders, data: {
      'retailerId': retailerId,
      'salesOfficerId': salesOfficerId,
      'isDirectSale': isDirectSale,
      'items': items,
      if (overrideCompanyId != null) 'overrideCompanyId': overrideCompanyId,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
    return OrderModel.fromJson(unwrap<Map<String, dynamic>>(response));
  }
}
