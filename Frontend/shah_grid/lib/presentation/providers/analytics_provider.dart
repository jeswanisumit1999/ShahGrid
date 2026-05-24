import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/analytics_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/retailer_model.dart';
import '../../data/repositories/analytics_repository.dart';
import '../../data/repositories/retailers_repository.dart';

final dashboardProvider = FutureProvider.autoDispose<DashboardModel>((ref) {
  return ref.read(analyticsRepositoryProvider).getDashboard();
});

final myStatsProvider = FutureProvider.autoDispose<MyStatsModel>((ref) {
  return ref.read(analyticsRepositoryProvider).getMyStats();
});

final stockAlertsProvider = FutureProvider.autoDispose<List<ProductModel>>((ref) {
  return ref.read(analyticsRepositoryProvider).getStockAlerts();
});

final godownStatsProvider = FutureProvider.autoDispose<GodownStatsModel>((ref) {
  return ref.read(analyticsRepositoryProvider).getGodownStats();
});

/// First page of retailers assigned to the current user — used on the Sales Officer dashboard.
final assignedRetailersProvider = FutureProvider.autoDispose<List<RetailerModel>>((ref) async {
  final result = await ref.read(retailersRepositoryProvider).list(limit: 20);
  return result.items;
});
