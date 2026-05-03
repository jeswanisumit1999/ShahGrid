import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/dio_client.dart';
import '../models/product_model.dart';
import '../models/user_model.dart';

final productsRepositoryProvider = Provider<ProductsRepository>((ref) {
  return ProductsRepository(ref.read(dioProvider));
});

class ProductsRepository {
  ProductsRepository(this._dio);
  final Dio _dio;

  Future<PaginatedResult<ProductModel>> list({
    String? cursor,
    int limit = 20,
    String? search,
    String? companyId,
    String? categoryId,
  }) async {
    final response = await _dio.get(ApiConstants.products, queryParameters: {
      if (cursor != null) 'cursor': cursor,
      'limit': limit,
      if (search != null && search.isNotEmpty) 'search': search,
      if (companyId != null) 'companyId': companyId,
      if (categoryId != null) 'categoryId': categoryId,
    });
    final body = response.data as Map<String, dynamic>;
    final pagination = body['pagination'] as Map<String, dynamic>? ?? {};
    return PaginatedResult(
      items: (body['data'] as List)
          .map((e) => ProductModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMore: pagination['hasMore'] as bool? ?? false,
      nextCursor: pagination['nextCursor'] as String?,
    );
  }

  Future<ProductModel> getById(String id) async {
    final response = await _dio.get(ApiConstants.productById(id));
    return ProductModel.fromJson(unwrap<Map<String, dynamic>>(response));
  }

  Future<ProductModel> create(Map<String, dynamic> data) async {
    final response = await _dio.post(ApiConstants.products, data: data);
    return ProductModel.fromJson(unwrap<Map<String, dynamic>>(response));
  }

  Future<ProductModel> adjustStock(String id, int delta, {String? reason}) async {
    final response = await _dio.post(ApiConstants.stockAdjust(id), data: {
      'delta': delta,
      if (reason != null) 'reason': reason,
    });
    return ProductModel.fromJson(unwrap<Map<String, dynamic>>(response));
  }

  Future<List<CompanySummary>> listCompanies() async {
    final response = await _dio.get(ApiConstants.companies);
    return (unwrap<List>(response))
        .map((e) => CompanySummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CompanySummary> createCompany(String name) async {
    final response = await _dio.post(ApiConstants.createCompany, data: {'name': name});
    return CompanySummary.fromJson(unwrap<Map<String, dynamic>>(response));
  }

  Future<List<CategorySummary>> listCategories() async {
    final response = await _dio.get(ApiConstants.categories);
    return (unwrap<List>(response))
        .map((e) => CategorySummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CategorySummary> createCategory(String name) async {
    final response = await _dio.post(ApiConstants.createCategory, data: {'name': name});
    return CategorySummary.fromJson(unwrap<Map<String, dynamic>>(response));
  }

  Future<List<String>> listBrands() async {
    final response = await _dio.get(ApiConstants.brands);
    return (unwrap<List>(response)).cast<String>();
  }
}
