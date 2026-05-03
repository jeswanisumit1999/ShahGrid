import 'product_model.dart';

class OrderModel {
  const OrderModel({
    required this.id,
    required this.retailerId,
    required this.createdById,
    required this.salesOfficerId,
    required this.totalAmount,
    required this.isDirectSale,
    required this.createdAt,
    this.retailerName,
    this.salesOfficerName,
    this.overrideCompanyId,
    this.notes,
    this.orderItems = const [],
    this.shipments = const [],
    this.payments = const [],
  });

  final String id;
  final String retailerId;
  final String? retailerName;
  final String createdById;
  final String salesOfficerId;
  final String? salesOfficerName;
  final double totalAmount;
  final bool isDirectSale;
  final String? overrideCompanyId;
  final String? notes;
  final String createdAt;
  final List<OrderItemModel> orderItems;
  final List<dynamic> shipments;
  final List<dynamic> payments;

  factory OrderModel.fromJson(Map<String, dynamic> json) => OrderModel(
        id: json['id'] as String,
        retailerId: json['retailerId'] as String,
        retailerName: (json['retailer'] as Map?)?.get('name'),
        createdById: json['createdById'] as String,
        salesOfficerId: json['salesOfficerId'] as String,
        salesOfficerName: (json['salesOfficer'] as Map?)?.get('name'),
        totalAmount: double.parse(json['totalAmount'].toString()),
        isDirectSale: json['isDirectSale'] as bool? ?? false,
        overrideCompanyId: json['overrideCompanyId'] as String?,
        notes: json['notes'] as String?,
        createdAt: json['createdAt'] as String,
        orderItems: (json['orderItems'] as List? ?? [])
            .map((e) => OrderItemModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        shipments: json['shipments'] as List? ?? [],
        payments: json['payments'] as List? ?? [],
      );
}

class OrderItemModel {
  const OrderItemModel({
    required this.id,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    this.deliveredQuantity,
    this.product,
  });

  final String id;
  final String productId;
  final int quantity;
  final double unitPrice;
  final int? deliveredQuantity;
  final ProductModel? product;

  double get lineTotal => quantity * unitPrice;

  factory OrderItemModel.fromJson(Map<String, dynamic> json) => OrderItemModel(
        id: json['id'] as String,
        productId: json['productId'] as String,
        quantity: json['quantity'] as int,
        unitPrice: double.parse(json['unitPrice'].toString()),
        deliveredQuantity: json['deliveredQuantity'] as int?,
        product: json['product'] != null
            ? ProductModel.fromJson(json['product'] as Map<String, dynamic>)
            : null,
      );
}

extension _MapExt on Map {
  String? get(String key) => this[key] as String?;
}
