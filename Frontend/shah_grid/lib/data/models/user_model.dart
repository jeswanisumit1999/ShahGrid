class UserModel {
  const UserModel({
    required this.id,
    required this.email,
    required this.name,
    required this.roles,
    required this.permissions,
    this.avatarUrl,
    this.isActive = true,
  });

  final String id;
  final String email;
  final String name;
  final List<String> roles;
  final List<String> permissions;
  final String? avatarUrl;
  final bool isActive;

  bool hasPermission(String resource, String action) =>
      permissions.contains('$resource.$action');

  bool hasRole(String role) => roles.contains(role);

  bool get isAdmin => hasRole('Admin');
  bool get isSupplyChain => hasRole('Supply Chain');
  bool get isSalesOfficer => hasRole('Sales Officer');
  bool get isGodownManager => hasRole('Godown Manager');

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] as String,
        email: json['email'] as String,
        name: json['name'] as String,
        roles: List<String>.from(json['roles'] as List? ?? []),
        permissions: List<String>.from(json['permissions'] as List? ?? []),
        avatarUrl: json['avatarUrl'] as String?,
        isActive: json['isActive'] as bool? ?? true,
      );
}

class PaginatedResult<T> {
  const PaginatedResult({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  final List<T> items;
  final bool hasMore;
  final String? nextCursor;
}
