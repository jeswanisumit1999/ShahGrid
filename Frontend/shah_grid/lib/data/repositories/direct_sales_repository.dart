import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/dio_client.dart';
import '../models/direct_sale_model.dart';
import '../models/user_model.dart';

final directSalesRepositoryProvider = Provider<DirectSalesRepository>((ref) {
  return DirectSalesRepository(ref.read(dioProvider));
});

class DirectSalesRepository {
  DirectSalesRepository(this._dio);
  final Dio _dio;

  Future<PaginatedResult<DirectSaleModel>> list({
    String? cursor,
    int limit = 20,
    String? salesOfficerId,
  }) async {
    final response = await _dio.get(ApiConstants.directSales, queryParameters: {
      if (cursor != null) 'cursor': cursor,
      'limit': limit,
      if (salesOfficerId != null) 'salesOfficerId': salesOfficerId,
    });
    final body = response.data as Map<String, dynamic>;
    final pagination = body['pagination'] as Map<String, dynamic>? ?? {};
    return PaginatedResult(
      items: (body['data'] as List)
          .map((e) => DirectSaleModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMore: pagination['hasMore'] as bool? ?? false,
      nextCursor: pagination['nextCursor'] as String?,
    );
  }

  Future<DirectSaleModel> getById(String id) async {
    final response = await _dio.get(ApiConstants.directSaleById(id));
    return DirectSaleModel.fromJson(unwrap<Map<String, dynamic>>(response));
  }

  Future<DirectSaleModel> create({
    required String customerName,
    required String salesOfficerId,
    required List<Map<String, dynamic>> items,
    double? amountPaid,
    String? notes,
  }) async {
    final response = await _dio.post(ApiConstants.directSales, data: {
      'customerName': customerName,
      'salesOfficerId': salesOfficerId,
      'items': items,
      if (amountPaid != null) 'amountPaid': amountPaid,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
    return DirectSaleModel.fromJson(unwrap<Map<String, dynamic>>(response));
  }

  Future<Uint8List> downloadChallan(String id) async {
    final response = await _dio.get<List<int>>(
      ApiConstants.directSaleChallan(id),
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data!);
  }
}
