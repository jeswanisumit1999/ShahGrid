import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/dio_client.dart';
import '../models/retailer_model.dart';
import '../models/retailer_ledger_model.dart';
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

  Future<void> deleteRetailer(String id) async {
    await _dio.delete(ApiConstants.retailerById(id));
  }

  Future<({int created, int skipped, List<String> errors})> importFromXls(
      Uint8List bytes, String fileName) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
    });
    final response = await _dio.post(ApiConstants.retailersImport, data: form);
    final data = unwrap<Map<String, dynamic>>(response);
    return (
      created: data['created'] as int,
      skipped: data['skipped'] as int,
      errors: (data['errors'] as List).cast<String>(),
    );
  }

  Future<Uint8List> downloadLedger(String retailerId) async {
    final response = await _dio.get<List<int>>(
      ApiConstants.retailerLedgerPdf(retailerId),
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data!);
  }

  Future<({List<RetailerLedgerEntry> items, bool hasMore, String? nextCursor, Map<String, dynamic> retailer})>
      getRetailerLedger(String retailerId, {String? cursor, int limit = 20}) async {
    final response = await _dio.get(ApiConstants.retailerLedger(retailerId), queryParameters: {
      if (cursor != null) 'cursor': cursor,
      'limit': limit,
    });
    final body = response.data as Map<String, dynamic>;
    final pagination = body['pagination'] as Map<String, dynamic>? ?? {};
    return (
      items: (body['data'] as List)
          .map((e) => RetailerLedgerEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMore: pagination['hasMore'] as bool? ?? false,
      nextCursor: pagination['nextCursor'] as String?,
      retailer: pagination['retailer'] as Map<String, dynamic>? ?? {},
    );
  }
}
