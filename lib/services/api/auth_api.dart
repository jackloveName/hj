import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'api_settings.dart';
import 'password_crypto.dart';

/// 登录与用户信息
class AuthApi {
  AuthApi(this._api);

  final ApiClient _api;

  /// 应用类型：H5 / 桌面端 4，Android 5，iOS 6，微信小程序 1
  static int get socialType => switch (defaultTargetPlatform) {
    TargetPlatform.android => 5,
    TargetPlatform.iOS => 6,
    _ => 4,
  };

  static String get osName => kIsWeb ? 'H5' : defaultTargetPlatform.name;

  /// 获取登录短信验证码（无需登录）
  Future<void> sendLoginCode({required String mobile}) async {
    await _api.put(
      '/mall_biz/ua/sms/verification_code/login_whocode',
      data: {'mobile': mobile},
      needToken: false,
      timeout: const Duration(seconds: 20),
    );
  }

  Map<String, Object?> _payload({
    required String phone,
    required bool byPassword,
    String? validCode,
    String? password,
  }) => {
    'sysType': 0,
    'socialType': socialType,
    'tempUid': '',
    'userName': phone,
    'appBrand': ApiSettings.appBrand,
    'osName': osName,
    'loginStatus': byPassword ? 2 : 1,
    if (byPassword)
      'passWord': encryptPassword(
        password ?? '',
        secret: ApiSettings.passwordSecret,
      )
    else ...{
      'mobile': phone,
      'validCode': validCode ?? '',
    },
  };

  /// 手机号验证码登录，返回访问凭证
  Future<String> loginWithCode({
    required String phone,
    required String validCode,
  }) async {
    final result = await _api.post(
      '/mall_auth/ua/login_with_code',
      data: _payload(phone: phone, byPassword: false, validCode: validCode),
      needToken: false,
    );
    return _accessTokenOf(result);
  }

  /// 手机号密码登录，返回访问凭证
  Future<String> loginWithPassword({
    required String phone,
    required String password,
  }) async {
    final result = await _api.post(
      '/mall_auth/ua/login',
      data: _payload(phone: phone, byPassword: true, password: password),
      needToken: false,
    );
    return _accessTokenOf(result);
  }

  /// 获取当前登录用户详情
  Future<Map<String, dynamic>> userDetail() async {
    final result = await _api.get('/mall_user/user/ma/user_detail_info');
    return unwrapUserRecord(result);
  }

  static String _accessTokenOf(Object? result) {
    final token = _findString(result, const [
      'accessToken',
      'access_token',
      'token',
    ]);
    if (token == null || token.isEmpty) {
      throw ApiException('登录响应中缺少访问凭证');
    }
    return token;
  }

  static String? _findString(Object? raw, List<String> keys, [int depth = 0]) {
    if (depth > 3 || raw is! Map) return null;
    final map = raw.map((k, v) => MapEntry(k.toString(), v));
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.isNotEmpty) return value;
    }
    for (final key in const ['data', 'userInfo', 'user']) {
      final found = _findString(map[key], keys, depth + 1);
      if (found != null) return found;
    }
    return null;
  }
}

/// 用户信息可能被包在 `data` / `userInfo` / `user` 里，逐层拆掉
Map<String, dynamic> unwrapUserRecord(Object? raw) {
  var value = raw is Map
      ? raw.map((k, v) => MapEntry(k.toString(), v))
      : <String, dynamic>{};
  for (var i = 0; i < 3; i++) {
    final nested = value['data'] ?? value['userInfo'] ?? value['user'];
    if (nested is Map) {
      value = nested.map((k, v) => MapEntry(k.toString(), v));
    } else {
      break;
    }
  }
  return value;
}
