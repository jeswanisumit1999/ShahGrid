import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/dio_client.dart';
import '../models/retailer_model.dart';
import '../models/user_model.dart';

final retailersRepositoryProvider = Provider<RetailersRepository>((ref) {
  return RetailersRepository(ref.read(dioProvider));
});

class RetailersRepository {
  RetailersRepository(this._dio);
  final Dio _dio;

  Future<PaginatedResult<RetailerModel>> list({
    String? cursor,
    int limit = 20,
    String? search,
    String? salesOfficerId,
  }) async {
    final response = await _dio.get(ApiConstants.retailers, queryParameters: {
      if (cursor != null) 'cursor': cursor,
      'limit': limit,
      if (search != null && search.isNotEmpty) 'search': search,
      if (salesOfficerId != null) 'salesOfficerId': salesOfficerId,
    });
    final body = response.data as Map<String, dynamic>;
    final pagination = body['pagination'] as Map<String, dynamic>? ?? {};
    return PaginatedResult(
      items: (body['data'] as List)
          .map((e) => RetailerModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMore: pagination['hasMore'] as bool? ?? false,
      nextCursor: pagination['nextCursor'] as String?,
    );
  }

  Future<RetailerModel> getById(String id) async {
    final response = await _dio.get(ApiConstants.retailerById(id));
    return RetailerModel.fromJson(unwrap<Map<String, dynamic>>(response));
  }

  Future<RetailerModel> create(Map<String, dynamic> data) async {
    final response = await _dio.post(ApiConstants.retailers, data: data);
    return RetailerModel.fromJson(unwrap<Map<String, dynamic>>(response));
  }

  Future<RetailerModel> update(String id, Map<String, dynamic> data) async {
    final response = await _dio.patch(ApiConstants.retailerById(id), data: data);
    return RetailerModel.fromJson(unwrap<Map<String, dynamic>>(response));
  }
}
