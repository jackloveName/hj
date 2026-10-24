import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/local_store.dart';
import 'api/api_settings.dart';
import 'token_store.dart';

/// 登录态：访问凭证、用户信息与数据作用域。
///
/// 未登录时作用域为 [guestScope]（游客 / 纯本机），登录后为手机号，
/// 因此云端数据键与本地缓存互不干扰。
class Session extends ChangeNotifier {
  /// [tokenStore] 不传就走本机存储（测试与桌面端都用默认值）；
  /// 移动端由 main.dart 传 SecureTokenStore，把 Token 放进 Keychain / Keystore。
  Session(this._store, {TokenStore? tokenStore})
    : _tokenStore = tokenStore ?? LocalTokenStore(_store, key: _tokenKey);

  static const String guestScope = 'GuestLocal';
  static const String _tokenKey = 'App-Token';
  static const String _userKey = 'zudun.user_info';
  static const String _authKey = 'zudun.auth';
  static const String _guestKey = 'zudun.guest_mode';
  static const String _installMarkerKey = 'zudun.install.initialized';
  final LocalStore _store;

  /// 访问凭证单独走一条通道：移动端进 Keychain / Keystore
  final TokenStore _tokenStore;

  String _token = '';
  String _phone = '';
  String _provider = '';
  Map<String, dynamic> _user = <String, dynamic>{};

  String get token => _token;
  String get phone => _phone;
  String get provider => _provider;
  Map<String, dynamic> get user => Map.unmodifiable(_user);

  bool get loggedIn => _token.isNotEmpty;

  /// 首页更新检查的业务门槛。后端可能下发数字或字符串，统一按数值 1 判断。
  bool get borrowFlagEnabled {
    final raw = _user['borrowFlag'];
    if (raw is num) return raw == 1;
    return double.tryParse('${raw ?? ''}'.trim()) == 1;
  }

  /// 是否已选择「游客模式」：首屏据此决定要不要先显示登录页
  bool get guestMode => _store.getString(_guestKey) == 'true';

  /// 进入游客模式：数据只留在本机内存里，不落盘
  Future<void> enterGuestMode() async {
    await _store.setString(_guestKey, 'true');
    notifyListeners();
  }

  String get nickName =>
      '${_user['nickName'] ?? _user['nickname'] ?? _user['userName'] ?? ''}'
          .trim();

  /// 头像路径（可能是云端路径）
  String get avatarPath => '${_user['pic'] ?? _user['avatar'] ?? ''}'.trim();

  /// 界面上显示的账号名
  String get displayName {
    if (nickName.isNotEmpty) return nickName;
    if (_phone.length >= 4) return '用户 ${_phone.substring(_phone.length - 4)}';
    return '已登录';
  }

  String get scope => loggedIn && _phone.isNotEmpty ? _phone : guestScope;

  /// 云端数据键：`${手机号}ZuDunData`
  String get dataKey => dataKeyOf(scope);

  /// 由作用域算数据键。清本机数据 / 注销时也必须用它，
  /// 否则 key 拼错就只是删掉一个不存在的键（老代码就是这么错的）。
  static String dataKeyOf(String scope) => '$scope${ApiSettings.dataKeySuffix}';

  /// 从本地恢复登录态
  Future<void> restore() async {
    await _clearOrphanedKeychainAfterReinstall();
    _token = await _tokenStore.read() ?? '';
    final rawUser = _store.getString(_userKey);
    if (rawUser != null && rawUser.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawUser);
        if (decoded is Map) {
          _user = decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (_) {
        _user = <String, dynamic>{};
      }
    }
    final rawAuth = _store.getString(_authKey);
    if (rawAuth != null && rawAuth.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawAuth);
        if (decoded is Map) {
          _phone = '${decoded['phone'] ?? ''}';
          _provider = '${decoded['provider'] ?? ''}';
        }
      } catch (_) {
        _phone = '';
      }
    }
  }

  /// iOS 卸载 App 不会自动删除 Keychain。用随 App 容器一起删除的安装标记识别
  /// 全新安装，并清掉上一份安装残留的 Token；普通升级会保留已有登录态。
  Future<void> _clearOrphanedKeychainAfterReinstall() async {
    if (_store.getString(_installMarkerKey) == 'true') return;
    final hasPreviousLocalSession =
        _store.getString(_authKey) != null ||
        _store.getString(_userKey) != null ||
        _store.getString(_guestKey) != null ||
        _store.getString('zudun.privacy.agreedVersion') != null;
    if (!hasPreviousLocalSession) {
      try {
        await _tokenStore.clear();
      } catch (error) {
        debugPrint('清理卸载残留 Token 失败：$error');
      }
    }
    await _store.setString(_installMarkerKey, 'true');
  }

  /// 登录成功：保存凭证与账号信息
  Future<void> saveLogin({
    required String token,
    required String phone,
    required String provider,
    Map<String, dynamic> user = const <String, dynamic>{},
  }) async {
    _token = token;
    _phone = phone;
    _provider = provider;
    _user = Map<String, dynamic>.from(user);
    // 登录后即退出游客模式标记，后续使用账号作用域
    await _store.remove(_guestKey);
    await _tokenStore.write(_token);
    await _store.setString(
      _authKey,
      jsonEncode({
        'phone': phone,
        'provider': provider,
        'loggedInAt': DateTime.now().toIso8601String(),
      }),
    );
    await _saveUser();
    notifyListeners();
  }

  /// 刷新用户详情（昵称 / 头像等）
  Future<void> updateUser(Map<String, dynamic> user) async {
    _user = Map<String, dynamic>.from(user);
    await _saveUser();
    notifyListeners();
  }

  Future<void> _saveUser() => _store.setString(_userKey, jsonEncode(_user));

  /// 退出登录：清空凭证，数据回到游客作用域
  Future<void> clear() async {
    _token = '';
    _phone = '';
    _provider = '';
    _user = <String, dynamic>{};
    await _tokenStore.clear();
    await _store.remove(_authKey);
    await _store.remove(_userKey);
    notifyListeners();
  }
}
