class PaymentModel {
  const PaymentModel({
    required this.id,
    required this.retailerId,
    required this.amount,
    required this.paymentDate,
    required this.method,
    required this.createdAt,
    this.orderId,
    this.retailerName,
    this.companyId,
    this.companyName,
    this.referenceNo,
    this.notes,
  });

  final String id;
  final String? orderId;
  final String retailerId;
  final String? retailerName;
  final String? companyId;
  final String? companyName;
  final double amount;
  final String paymentDate;
  final String method;
  final String? referenceNo;
  final String? notes;
  final String createdAt;

  static const List<String> methods = ['cash', 'upi', 'bank_transfer', 'cheque', 'other'];

  factory PaymentModel.fromJson(Map<String, dynamic> json) => PaymentModel(
        id: json['id'] as String? ?? '',
        orderId: json['orderId'] as String?,
        retailerId: json['retailerId'] as String? ?? '',
        retailerName: (json['retailer'] as Map?)?.mapGet('name'),
        companyId: json['companyId'] as String?,
        companyName: (json['company'] as Map?)?.mapGet('name'),
        amount: double.tryParse(json['amount']?.toString() ?? '') ?? 0,
        paymentDate: json['paymentDate'] as String? ?? '',
        method: json['method'] as String? ?? '',
        referenceNo: json['referenceNo'] as String?,
        notes: json['notes'] as String?,
        createdAt: json['createdAt'] as String? ?? '',
      );
}

extension _MapExt on Map {
  String? mapGet(String key) => this[key] as String?;
}
