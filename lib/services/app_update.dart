import 'dart:convert';

/// 服务端下发的版本信息
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    this.notes = '',
    this.url = '',
    this.force = false,
  });

  final String version;
  final String notes;
  final String url;

  /// 强制更新：弹窗不可关闭
  final bool force;
}

/// 点分版本号比较：a 比 b 新返回正数，相同返回 0
int compareVersions(String a, String b) {
  final left = _parts(a);
  final right = _parts(b);
  final length = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) return l - r;
  }
  return 0;
}

List<int> _parts(String value) => [
  for (final part in value.split(RegExp(r'[.\-+_]')))
    int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
];

/// 解析服务端配置。形态不固定（JSON 字符串 / `{paramValue: ...}` / 直接对象），
/// 尽量宽容地取版本号、更新说明与下载地址；取不到版本号视为「没有更新」。
AppUpdateInfo? parseAppUpdate(Object? raw) {
  final map = _unwrap(raw, 0);
  if (map == null) return null;
  final version = _string(map, const [
    'version',
    'versionName',
    'latestVersion',
    'newVersion',
    'appVersion',
  ]);
  if (version == null || version.trim().isEmpty) return null;
  return AppUpdateInfo(
    version: version.trim(),
    notes:
        _string(map, const [
          'notes',
          'note',
          'content',
          'desc',
          'description',
          'updateLog',
        ]) ??
        '',
    url:
        _string(map, const [
          'url',
          'downloadUrl',
          'androidUrl',
          'apkUrl',
          'iosUrl',
          'storeUrl',
        ]) ??
        '',
    force: _bool(map, const ['force', 'forceUpdate', 'isForce', 'mustUpdate']),
  );
}

Map<String, dynamic>? _unwrap(Object? raw, int depth) {
  if (raw == null || depth > 3) return null;
  if (raw is String) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    try {
      return _unwrap(jsonDecode(text), depth + 1);
    } catch (_) {
      return null;
    }
  }
  if (raw is Map) {
    final map = raw.map((key, value) => MapEntry(key.toString(), value));
    for (final key in const ['paramValue', 'value', 'data', 'config']) {
      final nested = map[key];
      if (nested is String || nested is Map) {
        final unwrapped = _unwrap(nested, depth + 1);
        if (unwrapped != null) return unwrapped;
      }
    }
    return map;
  }
  return null;
}

String? _string(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is num) return '$value';
  }
  return null;
}

bool _bool(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final text = value.trim().toLowerCase();
      if (text == 'true' || text == '1' || text == 'yes') return true;
    }
  }
  return false;
}
