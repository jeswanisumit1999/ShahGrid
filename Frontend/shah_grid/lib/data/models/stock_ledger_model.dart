class StockLedgerEntry {
  const StockLedgerEntry({
    required this.id,
    required this.productId,
    required this.delta,
    required this.balanceAfter,
    required this.type,
    required this.createdAt,
    this.referenceType,
    this.referenceId,
    this.notes,
    this.actorName,
  });

  final String id;
  final String productId;
  final int delta;
  final int balanceAfter;
  final String type;
  final String? referenceType;
  final String? referenceId;
  final String? notes;
  final String? actorName;
  final String createdAt;

  bool get isIn => delta > 0;

  String get label {
    switch (type) {
      case 'manual_in':          return 'Manual Stock In';
      case 'manual_out':         return 'Manual Stock Out';
      case 'dispatch_out':       return 'Dispatched';
      case 'dispatch_cancel_in': return 'Dispatch Cancelled';
      case 'delivery_short_in':  return 'Delivery Shortfall';
      case 'shipment_return_in': return 'Shipment Returned';
      case 'direct_sale_out':    return 'Direct Sale';
      case 'order_return_in':    return 'Order Return';
      default:                   return type;
    }
  }

  factory StockLedgerEntry.fromJson(Map<String, dynamic> json) => StockLedgerEntry(
        id: json['id'] as String,
        productId: json['productId'] as String? ?? '',
        delta: json['delta'] as int? ?? 0,
        balanceAfter: json['balanceAfter'] as int? ?? 0,
        type: json['type'] as String? ?? '',
        referenceType: json['referenceType'] as String?,
        referenceId: json['referenceId'] as String?,
        notes: json['notes'] as String?,
        actorName: json['actorName'] as String?,
        createdAt: json['createdAt'] as String? ?? '',
      );
}
