import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/dio_client.dart';
import '../models/shipment_model.dart';
import '../models/user_model.dart';

final shipmentsRepositoryProvider = Provider<ShipmentsRepository>((ref) {
  return ShipmentsRepository(ref.read(dioProvider));
});

class ItemAdjustment {
  const ItemAdjustment({required this.shipmentItemId, required this.actualQuantity});
  final String shipmentItemId;
  final int actualQuantity;
  Map<String, dynamic> toJson() =>
      {'shipmentItemId': shipmentItemId, 'actualQuantity': actualQuantity};
}

class ShipmentsRepository {
  ShipmentsRepository(this._dio);
  final Dio _dio;

  Future<PaginatedResult<ShipmentModel>> list({
    String? cursor,
    int limit = 20,
    String? orderId,
    String? status,
  }) async {
    final response = await _dio.get(ApiConstants.shipments, queryParameters: {
      if (cursor != null) 'cursor': cursor,
      'limit': limit,
      if (orderId != null) 'orderId': orderId,
      if (status != null) 'status': status,
    });
    final body = response.data as Map<String, dynamic>;
    final pagination = body['pagination'] as Map<String, dynamic>? ?? {};
    return PaginatedResult(
      items: (body['data'] as List)
          .map((e) => ShipmentModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMore: pagination['hasMore'] as bool? ?? false,
      nextCursor: pagination['nextCursor'] as String?,
    );
  }

  Future<ShipmentModel> getById(String id) async {
    final response = await _dio.get(ApiConstants.shipmentById(id));
    return ShipmentModel.fromJson(unwrap<Map<String, dynamic>>(response));
  }

  Future<ShipmentModel> updateStatus(
    String id,
    String status, {
    String? notes,
    List<ItemAdjustment>? adjustments,
    bool force = false,
  }) async {
    final response = await _dio.patch(ApiConstants.shipmentStatus(id), data: {
      'status': status,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (adjustments != null && adjustments.isNotEmpty)
        'adjustments': adjustments.map((a) => a.toJson()).toList(),
      if (force) 'force': true,
    });
    return ShipmentModel.fromJson(unwrap<Map<String, dynamic>>(response));
  }

  Future<Map<String, dynamic>> splitShipment(String id, List<String> itemIds) async {
    final response = await _dio.post(ApiConstants.shipmentSplit(id), data: {'itemIds': itemIds});
    return unwrap<Map<String, dynamic>>(response);
  }
}
