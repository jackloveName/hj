import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 服务端下发的版本信息
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    this.notes = '',
    this.url = '',
    this.logoUrl = '',
    this.force = false,
  });

  final String version;
  final String notes;
  final String url;
  final String logoUrl;

  /// 强制更新：弹窗不可关闭，与是否配置下载地址无关。
  final bool force;

  bool get blocking => force;
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

/// 服务端配置里有没有比 [current] 更新的版本。
/// 版本更新提示与下载地址是否配置无关，地址只影响弹窗里的按钮能否打开。
AppUpdateInfo? newerUpdate(
  Object? rawConfig,
  String current, {
  TargetPlatform? platform,
}) {
  final info = parseAppUpdate(rawConfig, platform: platform);
  if (info == null || compareVersions(info.version, current) <= 0) {
    return null;
  }
  return info;
}

List<int> _parts(String value) => [
  for (final part in value.split(RegExp(r'[.\-+_]')))
    int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
];

/// 解析服务端配置。形态不固定（JSON 字符串 / `{paramValue: ...}` / 直接对象），
/// 尽量宽容地取版本号、更新说明与下载地址；取不到版本号视为「没有更新」。
///
/// 平台后台的更新开关（`iosUpdateType` / `androidUpdateType`，与 jianzhirj 一致）：
/// **0 = 不更新**、**1 = 普通更新（可稍后）**、**2 = 强制更新**。
/// 字段缺失时保留通用配置兼容，也继续识别 `force` / `forceUpdate` 等布尔字段。
AppUpdateInfo? parseAppUpdate(Object? raw, {TargetPlatform? platform}) {
  final map = _unwrap(raw, 0);
  if (map == null) return null;
  final target = platform ?? defaultTargetPlatform;
  final updateSwitch = _updateSwitchOf(map, target);
  if (updateSwitch == 0) return null;
  final forceByType = updateSwitch == 2;
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
          'versionDesc',
          'iosVersionDesc',
          'androidVersionDesc',
          'iosUpdateContent',
          'androidUpdateContent',
        ]) ??
        '',
    url: _usableUrl(_string(map, _urlKeys(target))),
    logoUrl: _usableUrl(
      _string(map, const [
        'goodsLogo',
        'appLogo',
        'logoUrl',
        'appIcon',
        'iconUrl',
      ]),
    ),
    force:
        forceByType ||
        _bool(map, const ['force', 'forceUpdate', 'isForce', 'mustUpdate']),
  );
}

String _usableUrl(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return '';
  final host = Uri.tryParse(value)?.host.toLowerCase() ?? '';
  if (host.isEmpty) return '';
  return value;
}

/// 平台后台那套配置是**按平台分字段**存的（`iosAppVersion` / `androidVersion`、
/// `iosAppDownloadUrl` / `androidAppDownloadUrl`），所以先按当前平台挑一组，
/// 挑不到再退回通用字段（兼容别处下发的 `version` / `latestVersion` 这类写法）。
List<String> _versionKeys(TargetPlatform platform) => [
  ...switch (platform) {
    TargetPlatform.iOS => const ['iosAppVersion'],
    TargetPlatform.android => const ['androidVersion', 'androidAppVersion'],
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
    TargetPlatform.iOS => const ['iosAppDownloadUrl'],
    TargetPlatform.android => const ['androidAppDownloadUrl', 'androidUrl'],
    _ => const <String>[],
  },
  'h5DownloadUrl',
  'url',
  'downloadUrl',
  'storeUrl',
  'apkUrl',
];

/// 平台后台的更新开关：0 = 不更新、1 = 普通更新、2 = 强制更新；
/// 字段缺失返回 null（老写法 / 通用 payload 没有这个开关时继续兼容）。
int? _updateSwitchOf(Map<String, dynamic> map, TargetPlatform platform) {
  final keys = switch (platform) {
    TargetPlatform.iOS => const ['iosUpdateType'],
    TargetPlatform.android => const ['androidUpdateType'],
    _ => const <String>[],
  };
  for (final key in keys) {
    final value = map[key];
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
  }
  return null;
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
