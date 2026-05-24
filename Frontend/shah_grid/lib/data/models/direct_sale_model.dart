class DirectSaleModel {
  const DirectSaleModel({
    required this.id,
    required this.customerName,
    required this.salesOfficerId,
    required this.totalAmount,
    required this.createdAt,
    this.salesOfficerName,
    this.amountPaid,
    this.challanNumber,
    this.notes,
    this.items = const [],
  });

  final String id;
  final String customerName;
  final String salesOfficerId;
  final String? salesOfficerName;
  final double totalAmount;
  final double? amountPaid;
  final String? challanNumber;
  final String? notes;
  final String createdAt;
  final List<DirectSaleItemModel> items;

  double get balance => totalAmount - (amountPaid ?? 0);

  factory DirectSaleModel.fromJson(Map<String, dynamic> json) => DirectSaleModel(
        id: json['id'] as String,
        customerName: json['customerName'] as String,
        salesOfficerId: json['salesOfficerId'] as String,
        salesOfficerName: (json['salesOfficer'] as Map<String, dynamic>?)?['name'] as String?,
        totalAmount: double.parse((json['totalAmount'] ?? 0).toString()),
        amountPaid: json['amountPaid'] != null
            ? double.parse(json['amountPaid'].toString())
            : null,
        challanNumber: json['challanNumber'] as String?,
        notes: json['notes'] as String?,
        createdAt: json['createdAt'] as String? ?? '',
        items: (json['items'] as List<dynamic>? ?? [])
            .map((e) => DirectSaleItemModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class DirectSaleItemModel {
  const DirectSaleItemModel({
    required this.id,
    required this.directSaleId,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    this.productName,
    this.productSku,
  });

  final String id;
  final String directSaleId;
  final String productId;
  final String? productName;
  final String? productSku;
  final int quantity;
  final double unitPrice;

  double get lineTotal => quantity * unitPrice;

  factory DirectSaleItemModel.fromJson(Map<String, dynamic> json) => DirectSaleItemModel(
        id: json['id'] as String,
        directSaleId: json['directSaleId'] as String? ?? '',
        productId: json['productId'] as String,
        quantity: json['quantity'] as int,
        unitPrice: double.parse((json['unitPrice'] ?? 0).toString()),
        productName: (json['product'] as Map<String, dynamic>?)?['name'] as String?,
        productSku: (json['product'] as Map<String, dynamic>?)?['sku'] as String?,
      );
}
