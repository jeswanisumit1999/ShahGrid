import 'retailer_model.dart';
import 'product_model.dart';

/// Passed as GoRouter `extra` when navigating to /orders/new from a Reorder action.
class CreateOrderArgs {
  const CreateOrderArgs({required this.retailer, this.reorderItems = const []});
  final RetailerModel retailer;
  final List<ReorderItem> reorderItems;
}

class ReorderItem {
  const ReorderItem({required this.product, required this.qty, required this.unitPrice});
  final ProductModel product;
  final int qty;
  final double unitPrice;
}
