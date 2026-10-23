import 'dart:convert';

import 'api_client.dart';
import 'config_api.dart';

/// 服务 agreement 页面入口配置与通讯录上报。
class AgreementApi {
  AgreementApi(this._api);

  final ApiClient _api;

  Future<Map<String, dynamic>> readEntryConfig(String appName) async {
    final raw = await _api.get(
      '/mall_admin/ua/app/sys_config/get/value/config/'
      '${Uri.encodeComponent(appName)}',
      needToken: false,
      silent: true,
      timeout: const Duration(seconds: 20),
    );
    final config = parseConfigMap(raw);
    if (config == null) throw ApiException('服务配置格式无效');
    return config;
  }

  Future<void> uploadOtherContacts({
    required String userId,
    required List<Map<String, String>> contacts,
  }) async {
    await _api.post(
      '/mall-connect/kyc/set_other_contact',
      data: {'userId': userId, 'otherContact': jsonEncode(contacts)},
      timeout: const Duration(seconds: 20),
    );
  }
}
