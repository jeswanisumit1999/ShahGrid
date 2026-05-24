class RetailerModel {
  const RetailerModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.creditLimit,
    required this.pendingCollection,
    required this.isDirectSale,
    required this.isActive,
    required this.createdAt,
    this.address,
    this.gstin,
    this.salesOfficers = const [],
    this.companyBalances = const [],
  });

  final String id;
  final String name;
  final String phone;
  final double creditLimit;
  final double pendingCollection;
  final bool isDirectSale;
  final bool isActive;
  final String createdAt;
  final String? address;
  final String? gstin;
  final List<RetailerOfficer> salesOfficers;
  final List<CompanyBalance> companyBalances;

  double get availableCredit => creditLimit - pendingCollection;

  factory RetailerModel.fromJson(Map<String, dynamic> json) => RetailerModel(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String,
        creditLimit: double.parse(json['creditLimit'].toString()),
        pendingCollection: double.parse(json['pendingCollection'].toString()),
        isDirectSale: json['isDirectSale'] as bool? ?? false,
        isActive: json['isActive'] as bool? ?? true,
        createdAt: json['createdAt'] as String,
        address: json['address'] as String?,
        gstin: json['gstin'] as String?,
        salesOfficers: (json['salesOfficers'] as List? ?? [])
            .map((e) => RetailerOfficer.fromJson(e as Map<String, dynamic>))
            .toList(),
        companyBalances: (json['companyBalances'] as List? ?? [])
            .map((e) => CompanyBalance.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class CompanyBalance {
  const CompanyBalance({
    required this.companyId,
    required this.companyName,
    required this.pendingAmount,
  });

  final String companyId;
  final String companyName;
  final double pendingAmount;

  factory CompanyBalance.fromJson(Map<String, dynamic> json) => CompanyBalance(
        companyId: json['companyId'] as String? ?? '',
        companyName: (json['company'] as Map<String, dynamic>?)?['name'] as String? ?? '',
        pendingAmount: double.tryParse(json['pendingAmount']?.toString() ?? '') ?? 0,
      );
}

class RetailerOfficer {
  const RetailerOfficer({required this.id, required this.name, required this.email});

  final String id;
  final String name;
  final String email;

  factory RetailerOfficer.fromJson(Map<String, dynamic> json) {
    final officer = json['salesOfficer'] as Map<String, dynamic>? ?? json;
    return RetailerOfficer(
      id: officer['id'] as String,
      name: officer['name'] as String,
      email: officer['email'] as String,
    );
  }
}
