import 'dart:convert';

import 'package:flutter/foundation.dart';

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

  /// 要不要真的把用户拦住：**强制更新、而且确实有能用的下载地址**才算。
  /// 强制却没地址（比如后台还填着占位链接）时，弹窗关不掉就成了死胡同 ——
  /// 用户既装不上新版、也回不到 App，所以这种情况放行。
  bool get blocking => force && url.isNotEmpty;
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

/// 服务端配置里有没有比 [current] 更新的版本：
/// 没有配置、拿不到版本号、或者版本不比当前新，都返回 null（就是「没有更新」）。
AppUpdateInfo? newerUpdate(
  Object? rawConfig,
  String current, {
  TargetPlatform? platform,
}) {
  final info = parseAppUpdate(rawConfig, platform: platform);
  if (info == null || compareVersions(info.version, current) <= 0) return null;
  return info;
}

List<int> _parts(String value) => [
  for (final part in value.split(RegExp(r'[.\-+_]')))
    int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
];

/// 解析服务端配置。形态不固定（JSON 字符串 / `{paramValue: ...}` / 直接对象），
/// 尽量宽容地取版本号、更新说明与下载地址；取不到版本号视为「没有更新」。
AppUpdateInfo? parseAppUpdate(Object? raw, {TargetPlatform? platform}) {
  final map = _unwrap(raw, 0);
  if (map == null) return null;
  final target = platform ?? defaultTargetPlatform;
  final version = _string(map, _versionKeys(target));
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
          'iosUpdateContent',
          'androidUpdateContent',
        ]) ??
        '',
    url: _usableUrl(_string(map, _urlKeys(target))),
    force: _forceOf(map, target),
  );
}

/// 后台字段里的占位域名：`https://www.baidu.com` 这种只是「还没填」，
/// 发给用户只会把人带去无关站点，一律当「没有下载地址」——
/// 弹窗因此不显示「立即更新」，也就不会把人送错地方。
const Set<String> _placeholderHosts = {
  'baidu.com',
  'example.com',
  'example.org',
  'example.net',
  'test.com',
  'localhost',
  '127.0.0.1',
};

String _usableUrl(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return '';
  final host = Uri.tryParse(value)?.host.toLowerCase() ?? '';
  if (host.isEmpty) return '';
  for (final placeholder in _placeholderHosts) {
    if (host == placeholder || host.endsWith('.$placeholder')) return '';
  }
  return value;
}

/// 平台后台那套配置是**按平台分字段**存的（`iosAppVersion` / `androidVersion`、
/// `iosAppDownloadUrl` / `androidAppDownloadUrl`），所以先按当前平台挑一组，
/// 挑不到再退回通用字段（兼容别处下发的 `version` / `latestVersion` 这类写法）。
List<String> _versionKeys(TargetPlatform platform) => [
  ...switch (platform) {
    TargetPlatform.iOS => const ['iosAppVersion', 'iosVersion'],
    TargetPlatform.android => const ['androidAppVersion', 'androidVersion'],
    _ => const <String>[],
  },
  'version',
  'versionName',
  'latestVersion',
  'newVersion',
  'appVersion',
];

List<String> _urlKeys(TargetPlatform platform) => [
  ...switch (platform) {
    TargetPlatform.iOS => const [
      'iosAppDownloadUrl',
      'iosDownloadUrl',
      'iosUrl',
    ],
    TargetPlatform.android => const [
      'androidAppDownloadUrl',
      'androidDownloadUrl',
      'androidUrl',
    ],
    _ => const <String>[],
  },
  'url',
  'downloadUrl',
  'storeUrl',
  'apkUrl',
];

/// 强制更新：通用字段（`force` / `forceUpdate` …）算数；平台后台那套
/// `iosUpdateType` / `androidUpdateType` 只在 **≥ 2** 时当强制
/// （1 是「有新版本就提示」，弹窗可以关掉）。
bool _forceOf(Map<String, dynamic> map, TargetPlatform platform) {
  if (_bool(map, const ['force', 'forceUpdate', 'isForce', 'mustUpdate'])) {
    return true;
  }
  final keys = switch (platform) {
    TargetPlatform.iOS => const ['iosUpdateType', 'iosForceUpdate'],
    TargetPlatform.android => const ['androidUpdateType', 'androidForceUpdate'],
    _ => const <String>[],
  };
  return _intOf(map, keys) >= 2;
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

int _intOf(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
  }
  return 0;
}
