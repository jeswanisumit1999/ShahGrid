class ShipmentModel {
  const ShipmentModel({
    required this.id,
    required this.orderId,
    required this.companyId,
    required this.status,
    required this.createdAt,
    this.companyName,
    this.retailerName,
    this.readyAt,
    this.deliveredAt,
    this.returnedAt,
    this.notes,
    this.shipmentItems = const [],
  });

  final String id;
  final String orderId;
  final String companyId;
  final String? companyName;
  final String? retailerName;
  final String status;
  final String? readyAt;
  final String? deliveredAt;
  final String? returnedAt;
  final String? notes;
  final String createdAt;
  final List<ShipmentItemModel> shipmentItems;

  static const List<String> allStatuses = [
    'Pending Stock Verification',
    'Pending Stock Availability',
    'Ready for Dispatch',
    'Delivered',
    'Cancelled',
    'Returned',
  ];

  bool get isTerminal =>
      status == 'Delivered' || status == 'Cancelled' || status == 'Returned';

  bool get canSplit =>
      status == 'Pending Stock Verification' || status == 'Pending Stock Availability';

  factory ShipmentModel.fromJson(Map<String, dynamic> json) => ShipmentModel(
        id: json['id'] as String,
        orderId: json['orderId'] as String,
        companyId: json['companyId'] as String,
        companyName: (json['company'] as Map<String, dynamic>?)?['name'] as String?,
        retailerName:
            ((json['order'] as Map<String, dynamic>?)?['retailer'] as Map<String, dynamic>?)?['name']
                as String?,
        status: json['status'] as String,
        readyAt: json['readyAt'] as String?,
        deliveredAt: json['deliveredAt'] as String?,
        returnedAt: json['returnedAt'] as String?,
        notes: json['notes'] as String?,
        createdAt: json['createdAt'] as String,
        shipmentItems: (json['shipmentItems'] as List? ?? [])
            .map((e) => ShipmentItemModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ShipmentItemModel {
  const ShipmentItemModel({
    required this.id,
    required this.shipmentId,
    required this.orderItemId,
    required this.quantity,
    required this.status,
    this.productId,
    this.productName,
    this.productSku,
    this.unitPrice,
  });

  final String id;
  final String shipmentId;
  final String orderItemId;
  final int quantity;
  final String status;
  final String? productId;
  final String? productName;
  final String? productSku;
  final double? unitPrice;

  factory ShipmentItemModel.fromJson(Map<String, dynamic> json) {
    final orderItem = json['orderItem'] as Map<String, dynamic>?;
    final product = orderItem?['product'] as Map<String, dynamic>?;
    return ShipmentItemModel(
      id: json['id'] as String,
      shipmentId: json['shipmentId'] as String,
      orderItemId: json['orderItemId'] as String,
      quantity: json['quantity'] as int,
      status: json['status'] as String? ?? 'pending',
      productId: product?['id'] as String?,
      productName: product?['name'] as String?,
      productSku: product?['sku'] as String?,
      unitPrice: orderItem != null
          ? double.tryParse(orderItem['unitPrice']?.toString() ?? '')
          : null,
    );
  }
}
