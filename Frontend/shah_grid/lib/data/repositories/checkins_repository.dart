import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/dio_client.dart';
import '../models/checkin_model.dart';
import '../models/user_model.dart';

final checkInsRepositoryProvider = Provider<CheckInsRepository>((ref) {
  return CheckInsRepository(ref.read(dioProvider));
});

class CheckInsRepository {
  CheckInsRepository(this._dio);
  final Dio _dio;

  Future<PaginatedResult<CheckInModel>> list({
    String? cursor,
    int limit = 20,
    String? userId,
  }) async {
    final response = await _dio.get(ApiConstants.checkins, queryParameters: {
      if (cursor != null) 'cursor': cursor,
      'limit': limit,
      if (userId != null) 'userId': userId,
    });
    final body = response.data as Map<String, dynamic>;
    final pagination = body['pagination'] as Map<String, dynamic>? ?? {};
    return PaginatedResult(
      items: (body['data'] as List)
          .map((e) => CheckInModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMore: pagination['hasMore'] as bool? ?? false,
      nextCursor: pagination['nextCursor'] as String?,
    );
  }

  Future<CheckInModel> create({
    required double latitude,
    required double longitude,
    String? notes,
  }) async {
    final response = await _dio.post(ApiConstants.checkins, data: {
      'latitude': latitude,
      'longitude': longitude,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
    final body = response.data as Map<String, dynamic>;
    return CheckInModel.fromJson(body['data'] as Map<String, dynamic>);
  }
}
