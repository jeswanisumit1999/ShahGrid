import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/dio_client.dart';
import '../models/analytics_model.dart';
import '../models/product_model.dart';

final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  return AnalyticsRepository(ref.read(dioProvider));
});

class AnalyticsRepository {
  AnalyticsRepository(this._dio);
  final Dio _dio;

  Future<DashboardModel> getDashboard() async {
    final response = await _dio.get(ApiConstants.dashboard);
    return DashboardModel.fromJson(unwrap<Map<String, dynamic>>(response));
  }

  Future<MyStatsModel> getMyStats() async {
    final response = await _dio.get(ApiConstants.myStats);
    return MyStatsModel.fromJson(unwrap<Map<String, dynamic>>(response));
  }

  Future<List<ProductModel>> getStockAlerts({int threshold = 10}) async {
    final response = await _dio.get(
      ApiConstants.stockAlerts,
      queryParameters: {'threshold': threshold},
    );
    return (unwrap<List>(response))
        .map((e) => ProductModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
