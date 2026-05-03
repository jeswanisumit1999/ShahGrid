import 'order_model.dart';
import 'product_model.dart';

class DashboardModel {
  const DashboardModel({
    required this.totalOrders,
    required this.totalRetailers,
    required this.totalPendingCollection,
    required this.recentOrders,
  });

  final int totalOrders;
  final int totalRetailers;
  final double totalPendingCollection;
  final List<OrderModel> recentOrders;

  factory DashboardModel.fromJson(Map<String, dynamic> json) => DashboardModel(
        totalOrders: json['totalOrders'] as int? ?? 0,
        totalRetailers: json['totalRetailers'] as int? ?? 0,
        totalPendingCollection:
            double.parse((json['totalPendingCollection'] ?? 0).toString()),
        recentOrders: (json['recentOrders'] as List? ?? [])
            .map((e) => OrderModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class MyStatsModel {
  const MyStatsModel({
    required this.orderCount,
    required this.visitCount,
    required this.totalPaymentsCollected,
  });

  final int orderCount;
  final int visitCount;
  final double totalPaymentsCollected;

  factory MyStatsModel.fromJson(Map<String, dynamic> json) => MyStatsModel(
        orderCount: json['orderCount'] as int? ?? 0,
        visitCount: json['visitCount'] as int? ?? 0,
        totalPaymentsCollected:
            double.parse((json['totalPaymentsCollected'] ?? 0).toString()),
      );
}
