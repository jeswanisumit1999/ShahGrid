class PermissionModel {
  const PermissionModel({required this.id, required this.resource, required this.action});
  final String id;
  final String resource;
  final String action;
  String get key => '$resource.$action';

  factory PermissionModel.fromJson(Map<String, dynamic> j) => PermissionModel(
        id: j['id'] as String,
        resource: j['resource'] as String,
        action: j['action'] as String,
      );
}

class RoleModel {
  const RoleModel({
    required this.id,
    required this.name,
    required this.isSystemRole,
    required this.permissions,
    this.description,
  });
  final String id;
  final String name;
  final String? description;
  final bool isSystemRole;
  final List<PermissionModel> permissions;

  factory RoleModel.fromJson(Map<String, dynamic> j) => RoleModel(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        isSystemRole: j['isSystemRole'] as bool? ?? false,
        permissions: ((j['rolePermissions'] as List?) ?? [])
            .map((e) => PermissionModel.fromJson(
                (e as Map<String, dynamic>)['permission'] as Map<String, dynamic>))
            .toList(),
      );
}

class AdminUserModel {
  const AdminUserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.isActive,
    this.avatarUrl,
    this.roleName,
    this.roleId,
  });
  final String id;
  final String name;
  final String email;
  final bool isActive;
  final String? avatarUrl;
  final String? roleName;
  final String? roleId;

  factory AdminUserModel.fromJson(Map<String, dynamic> j) {
    final userRoles = j['userRoles'] as List? ?? [];
    final firstRole = userRoles.isNotEmpty ? userRoles.first as Map<String, dynamic> : null;
    final role = firstRole?['role'] as Map<String, dynamic>?;
    return AdminUserModel(
      id: j['id'] as String,
      name: j['name'] as String? ?? '',
      email: j['email'] as String,
      isActive: j['isActive'] as bool? ?? true,
      avatarUrl: j['avatarUrl'] as String?,
      roleName: role?['name'] as String?,
      roleId: role?['id'] as String?,
    );
  }
}

class ActivityLogEntry {
  const ActivityLogEntry({
    required this.id,
    required this.actorId,
    required this.actorName,
    required this.actorEmail,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.createdAt,
    this.entityLabel,
    this.diff,
  });

  final String id;
  final String actorId;
  final String actorName;
  final String actorEmail;
  final String action;
  final String entityType;
  final String entityId;
  final String? entityLabel;
  final DateTime createdAt;
  final Map<String, dynamic>? diff;

  factory ActivityLogEntry.fromJson(Map<String, dynamic> j) => ActivityLogEntry(
        id: j['id'] as String,
        actorId: j['actorId'] as String,
        actorName: j['actorName'] as String? ?? 'Unknown',
        actorEmail: j['actorEmail'] as String? ?? '',
        action: j['action'] as String,
        entityType: j['entityType'] as String,
        entityId: j['entityId'] as String,
        entityLabel: j['entityLabel'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
        diff: j['diff'] as Map<String, dynamic>?,
      );
}
