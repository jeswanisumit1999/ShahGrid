import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/analytics_model.dart';
import '../../data/models/product_model.dart';
import '../../data/repositories/analytics_repository.dart';

final dashboardProvider = FutureProvider.autoDispose<DashboardModel>((ref) {
  return ref.read(analyticsRepositoryProvider).getDashboard();
});

final myStatsProvider = FutureProvider.autoDispose<MyStatsModel>((ref) {
  return ref.read(analyticsRepositoryProvider).getMyStats();
});

final stockAlertsProvider = FutureProvider.autoDispose<List<ProductModel>>((ref) {
  return ref.read(analyticsRepositoryProvider).getStockAlerts();
});
