class RetailerLedgerEntry {
  const RetailerLedgerEntry({
    required this.id,
    required this.retailerId,
    required this.delta,
    required this.balanceAfter,
    required this.type,
    required this.createdAt,
    this.companyId,
    this.companyName,
    this.referenceType,
    this.referenceId,
    this.actorName,
    this.notes,
  });

  final String id;
  final String retailerId;
  final String? companyId;
  final String? companyName;
  final double delta;
  final double balanceAfter;
  final String type;
  final String? referenceType;
  final String? referenceId;
  final String? actorName;
  final String? notes;
  final String createdAt;

  bool get isDebit => delta > 0;

  String get label {
    switch (type) {
      case 'order_debit':
        return 'Order Placed';
      case 'item_added':
        return 'Item Added';
      case 'qty_adjusted':
        return delta > 0 ? 'Qty Increased' : 'Qty Decreased';
      case 'payment_credit':
        return 'Payment Received';
      case 'return_credit':
        return 'Return Credit';
      case 'delivery_adjustment':
        return 'Delivery Adjusted';
      case 'shipment_return':
        return 'Shipment Returned';
      default:
        return type;
    }
  }

  factory RetailerLedgerEntry.fromJson(Map<String, dynamic> json) =>
      RetailerLedgerEntry(
        id: json['id'] as String,
        retailerId: json['retailerId'] as String,
        companyId: json['companyId'] as String?,
        companyName: json['companyName'] as String?,
        delta: double.tryParse(json['delta']?.toString() ?? '') ?? 0,
        balanceAfter:
            double.tryParse(json['balanceAfter']?.toString() ?? '') ?? 0,
        type: json['type'] as String,
        referenceType: json['referenceType'] as String?,
        referenceId: json['referenceId'] as String?,
        actorName: json['actorName'] as String?,
        notes: json['notes'] as String?,
        createdAt: json['createdAt'] as String,
      );
}
