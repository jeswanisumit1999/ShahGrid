import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/dio_client.dart';
import '../models/settings_model.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.read(dioProvider));
});

class SettingsRepository {
  SettingsRepository(this._dio);
  final Dio _dio;

  Future<List<AppSetting>> list() async {
    final response = await _dio.get(ApiConstants.settings);
    return (unwrap<List>(response))
        .map((e) => AppSetting.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AppSetting> update(String key, String value) async {
    final response = await _dio.patch(
      ApiConstants.settingByKey(key),
      data: {'value': value},
    );
    return AppSetting.fromJson(unwrap<Map<String, dynamic>>(response));
  }
}
