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
    : _tokenStore =
          tokenStore ?? LocalTokenStore(_store, key: _tokenKey);

  static const String guestScope = 'GuestLocal';
  static const String _tokenKey = 'App-Token';
  static const String _userKey = 'zudun.user_info';
  static const String _authKey = 'zudun.auth';
  static const String _guestKey = 'zudun.guest_mode';
  static const String _firstSeenKey = 'zudun.first_seen_at';
  final LocalStore _store;

  /// 访问凭证单独走一条通道：移动端进 Keychain / Keystore
  final TokenStore _tokenStore;

  String _token = '';
  String _phone = '';
  String _provider = '';
  Map<String, dynamic> _user = <String, dynamic>{};
  DateTime? _firstSeenAt;

  String get token => _token;
  String get phone => _phone;
  String get provider => _provider;
  Map<String, dynamic> get user => Map.unmodifiable(_user);

  bool get loggedIn => _token.isNotEmpty;

  /// 用户首次打开 app / 登录的时间：未记录过则返回 null
  DateTime? get firstSeenAt => _firstSeenAt;

  /// 从首次使用到今天的「流浪天数」：未记录返回 0
  int get daysSinceFirstSeen {
    final start = _firstSeenAt;
    if (start == null) return 0;
    final today = DateTime.now();
    final days = DateTime(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime(start.year, start.month, start.day)).inDays;
    return days < 0 ? 0 : days;
  }

  /// 是否已选择「本机模式」：首屏据此决定要不要先显示登录页
  bool get guestMode => _store.getString(_guestKey) == 'true';

  /// 进入本机（游客）模式：同样记录首次使用时间，用于「流浪」文案
  Future<void> enterGuestMode() async {
    await ensureFirstSeen();
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
    final rawFirstSeen = _store.getString(_firstSeenKey);
    if (rawFirstSeen != null && rawFirstSeen.isNotEmpty) {
      _firstSeenAt = DateTime.tryParse(rawFirstSeen);
    }
  }

  /// 首次进入时记录起点：已存在则不覆盖。
  /// 由 [CloudService.restore] 在启动时无条件调用，确保新用户首启即落地。
  Future<void> ensureFirstSeen() async {
    if (_firstSeenAt != null) return;
    final existing = _store.getString(_firstSeenKey);
    if (existing != null && existing.isNotEmpty) {
      _firstSeenAt = DateTime.tryParse(existing);
      if (_firstSeenAt != null) return;
    }
    _firstSeenAt = DateTime.now();
    await _store.setString(_firstSeenKey, _firstSeenAt!.toIso8601String());
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
    await ensureFirstSeen();
    // 登录后即退出本机模式标记，后续使用账号作用域
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

  Future<void> _saveUser() =>
      _store.setString(_userKey, jsonEncode(_user));

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
