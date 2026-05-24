import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/dio_client.dart';
import '../models/admin_models.dart';
import '../models/user_model.dart';

final usersRepositoryProvider = Provider<UsersRepository>((ref) {
  return UsersRepository(ref.read(dioProvider));
});

class UsersRepository {
  UsersRepository(this._dio);
  final Dio _dio;

  Future<PaginatedResult<AdminUserModel>> listUsers({
    String? cursor,
    int limit = 20,
    String? search,
  }) async {
    final response = await _dio.get(ApiConstants.users, queryParameters: {
      if (cursor != null) 'cursor': cursor,
      'limit': limit,
      if (search != null && search.isNotEmpty) 'search': search,
    });
    final body = response.data as Map<String, dynamic>;
    final pagination = body['pagination'] as Map<String, dynamic>? ?? {};
    return PaginatedResult(
      items: (body['data'] as List)
          .map((e) => AdminUserModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMore: pagination['hasMore'] as bool? ?? false,
      nextCursor: pagination['nextCursor'] as String?,
    );
  }

  Future<List<RoleModel>> listRoles() async {
    final response = await _dio.get(ApiConstants.roles);
    return (unwrap<List>(response))
        .map((e) => RoleModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<PermissionModel>> listPermissions() async {
    final response = await _dio.get(ApiConstants.permissions);
    return (unwrap<List>(response))
        .map((e) => PermissionModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RoleModel> createRole({
    required String name,
    String? description,
    required List<String> permissionIds,
  }) async {
    final response = await _dio.post(ApiConstants.roles, data: {
      'name': name,
      if (description != null && description.isNotEmpty) 'description': description,
      'permissionIds': permissionIds,
    });
    return RoleModel.fromJson(unwrap<Map<String, dynamic>>(response));
  }

  Future<void> deleteRole(String roleId) async {
    await _dio.delete(ApiConstants.roleById(roleId));
  }

  Future<void> assignRole({required String userId, required String roleId}) async {
    await _dio.post(ApiConstants.assignRole, data: {'userId': userId, 'roleId': roleId});
  }

  Future<void> deactivateUser(String userId) async {
    await _dio.patch(ApiConstants.deactivateUser(userId));
  }

  Future<RoleModel> updateRolePermissions(String roleId, List<String> permissionIds) async {
    final response = await _dio.patch(
      ApiConstants.rolePermissions(roleId),
      data: {'permissionIds': permissionIds},
    );
    return RoleModel.fromJson(unwrap<Map<String, dynamic>>(response));
  }

  Future<PaginatedResult<ActivityLogEntry>> listActivityLog({
    String? cursor,
    int limit = 30,
    String? search,
  }) async {
    final response = await _dio.get(ApiConstants.activityLog, queryParameters: {
      if (cursor != null) 'cursor': cursor,
      'limit': limit,
      if (search != null && search.isNotEmpty) 'search': search,
    });
    final body = response.data as Map<String, dynamic>;
    final pagination = body['pagination'] as Map<String, dynamic>? ?? {};
    return PaginatedResult(
      items: (body['data'] as List)
          .map((e) => ActivityLogEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMore: pagination['hasMore'] as bool? ?? false,
      nextCursor: pagination['nextCursor'] as String?,
    );
  }
}
