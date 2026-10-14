import '../../data/local_store.dart';

/// 接口层配置：网关地址、对象存储域名、应用标识。
///
/// 网关与对象存储的默认值由服务端提供，可在「我的 → 账号与同步 → 服务器地址」里改。
class ApiSettings {
  ApiSettings(this._store);

  static const String defaultBaseUrl = 'https://dmjz.makcabxa02y.icu';

  /// 对象存储的公开访问前缀（首次上传时会按预签名地址自动校正）
  static const String defaultOssBaseUrl =
      'https://mizhenhl.oss-cn-beijing.aliyuncs.com';

  /// 登录时提交的应用标识
  static const String appBrand = '租盾';

  /// 登录密码传输加密密钥（与平台前端一致）
  static const String passwordSecret = '-mall--password-';

  /// 云端数据键后缀：完整键为 `${手机号}ZuDunData`
  static const String dataKeySuffix = 'ZuDunData';

  static const String _baseUrlKey = 'zudun.api.base_url';
  static const String _ossBaseKey = 'zudun.api.oss_base_url';

  final LocalStore _store;

  String get baseUrl => _nonEmpty(_store.getString(_baseUrlKey)) ?? defaultBaseUrl;

  String get ossBaseUrl =>
      _nonEmpty(_store.getString(_ossBaseKey)) ?? defaultOssBaseUrl;

  Future<void> setBaseUrl(String value) async {
    final normalized = _normalizeUrl(value);
    if (normalized == null) return;
    await _store.setString(_baseUrlKey, normalized);
  }

  Future<void> setOssBaseUrl(String value) async {
    final origin = originOf(value);
    if (origin == null) return;
    await _store.setString(_ossBaseKey, origin);
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _normalizeUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final withScheme = trimmed.startsWith('http') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) return null;
    // 去掉结尾的斜杠，方便直接拼 path
    return withScheme.endsWith('/')
        ? withScheme.substring(0, withScheme.length - 1)
        : withScheme;
  }

  /// 取 `scheme://host`，用于把资源路径拼成可访问的地址
  static String? originOf(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return null;
    final scheme = uri.scheme.isEmpty ? 'https' : uri.scheme;
    return '$scheme://${uri.host}';
  }
}
