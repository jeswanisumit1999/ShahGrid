class ProductModel {
  const ProductModel({
    required this.id,
    required this.companyId,
    required this.name,
    required this.price,
    required this.stockQuantity,
    required this.isActive,
    required this.createdAt,
    this.sku,
    this.brand,
    this.categoryId,
    this.lowStockThreshold,
    this.company,
    this.category,
  });

  final String id;
  final String companyId;
  final String? categoryId;
  final String name;
  final String? sku;
  final String? brand;
  final double price;
  final int stockQuantity;
  final int? lowStockThreshold;
  final bool isActive;
  final String createdAt;
  final CompanySummary? company;
  final CategorySummary? category;

  bool get isLowStock =>
      lowStockThreshold != null && stockQuantity <= lowStockThreshold!;

  factory ProductModel.fromJson(Map<String, dynamic> json) => ProductModel(
        id: json['id'] as String,
        companyId: json['companyId'] as String? ?? '',
        categoryId: json['categoryId'] as String?,
        name: json['name'] as String,
        sku: json['sku'] as String?,
        brand: json['brand'] as String?,
        price: double.parse((json['price'] ?? 0).toString()),
        stockQuantity: json['stockQuantity'] as int? ?? 0,
        lowStockThreshold: json['lowStockThreshold'] as int?,
        isActive: json['isActive'] as bool? ?? true,
        createdAt: json['createdAt'] as String? ?? '',
        company: json['company'] != null
            ? CompanySummary.fromJson(json['company'] as Map<String, dynamic>)
            : null,
        category: json['category'] != null
            ? CategorySummary.fromJson(json['category'] as Map<String, dynamic>)
            : null,
      );
}

class CompanySummary {
  const CompanySummary({required this.id, required this.name, this.gstin, this.phone, this.address});
  final String id;
  final String name;
  final String? gstin;
  final String? phone;
  final String? address;
  factory CompanySummary.fromJson(Map<String, dynamic> j) => CompanySummary(
        id: j['id'] as String,
        name: j['name'] as String,
        gstin: j['gstin'] as String?,
        phone: j['phone'] as String?,
        address: j['address'] as String?,
      );
}

class CategorySummary {
  const CategorySummary({required this.id, required this.name});
  final String id;
  final String name;
  factory CategorySummary.fromJson(Map<String, dynamic> j) =>
      CategorySummary(id: j['id'] as String, name: j['name'] as String);
}
