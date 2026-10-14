import 'dart:convert';

import 'api_client.dart';

/// 系统配置 / 用户配置读写
class ConfigApi {
  ConfigApi(this._api);

  final ApiClient _api;

  /// 读取用户级配置：返回原始响应（字符串或对象）
  Future<Object?> readUserConfig(String key) => _api.get(
    '/mall_admin/ua/app/sys_config/get/other/value/config/${Uri.encodeComponent(key)}',
  );

  /// 覆盖写入用户级配置
  Future<void> saveUserConfig({
    required String paramKey,
    required String paramValue,
    required String remark,
  }) => _api.post(
    '/mall_admin/p/sys_config/ua/other/save',
    data: {'paramKey': paramKey, 'paramValue': paramValue, 'remark': remark},
  );

  /// 读取系统公共配置（协议 / 版本更新等），无需登录
  Future<Object?> readSystemConfig(String key) => _api.get(
    '/mall_admin/ua/app/sys_config/get/value/config/${Uri.encodeComponent(key)}',
    needToken: false,
    silent: true,
    timeout: const Duration(seconds: 20),
  );
}

/// 归一化用户配置：可能是 JSON 字符串、`{paramValue: "..."}`，或 `{data: {...}}`
Map<String, dynamic>? parseConfigMap(Object? raw) {
  var value = raw;
  for (var i = 0; i < 3; i++) {
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty) return null;
      try {
        value = jsonDecode(text);
      } catch (_) {
        return null;
      }
      continue;
    }
    if (value is Map) {
      final map = value.map((k, v) => MapEntry(k.toString(), v));
      if (map['paramValue'] is String) {
        value = map['paramValue'];
        continue;
      }
      if (map['data'] is Map) {
        value = map['data'];
        continue;
      }
      return map;
    }
    return null;
  }
  return value is Map
      ? value.map((k, v) => MapEntry(k.toString(), v))
      : null;
}
