import 'dart:convert';

import 'api/api_client.dart';
import 'api/config_api.dart';

/// 当前协议版本：协议有实质更新时把这个数字 +1，
/// 老用户下次启动会被重新征询同意。
const String zudunProtocolVersion = '1';

/// 协议种类
enum ProtocolKind {
  /// 隐私政策
  privacy,

  /// 平台注册协议
  agreement,
}

/// 协议正文服务：**只从服务端下发读取，不做本地兜底**。
///
/// - 键名：隐私政策 `ZD_PRIVACY_PROTOC`、平台注册协议 `ZD_REGISTER_PROTOC`；
/// - 接口：`/mall_admin/ua/app/sys_config/get/value/config/{key}`（免登录）；
/// - 结果同一会话内缓存 5 分钟；服务端没配或请求失败时抛 [ApiException]，
///   由界面显示「协议加载失败 + 重试」，不再拿旧文本顶上。
class ProtocolService {
  ProtocolService(this._config);

  final ConfigApi _config;

  static const Duration cacheTtl = Duration(minutes: 5);
  final Map<ProtocolKind, ({String text, DateTime at})> _cache = {};

  static String keyOf(ProtocolKind kind) => switch (kind) {
    ProtocolKind.privacy => 'ZD_PRIVACY_PROTOC',
    ProtocolKind.agreement => 'ZD_REGISTER_PROTOC',
  };

  /// 读取协议正文；[refresh] 为 true 时忽略缓存（重试按钮用）
  Future<String> load(ProtocolKind kind, {bool refresh = false}) async {
    final cached = _cache[kind];
    if (!refresh &&
        cached != null &&
        DateTime.now().difference(cached.at) < cacheTtl) {
      return cached.text;
    }
    final raw = await _config.readSystemConfig(keyOf(kind));
    final text = protocolPlainText(raw);
    if (text.isEmpty) {
      throw ApiException('协议内容暂不可用，请检查网络后重试');
    }
    _cache[kind] = (text: text, at: DateTime.now());
    return text;
  }

  void clear() => _cache.clear();
}

/// 服务端可能下发 JSON 字符串、`{paramValue: ...}` 或 HTML，统一成纯文本
String protocolPlainText(Object? raw) => _plain(raw, 0).trim();

String _plain(Object? raw, int depth) {
  if (raw == null || depth > 3) return '';
  if (raw is String) {
    final text = raw.trim();
    if (text.isEmpty) return '';
    // 有的环境把内容再包一层 JSON 字符串
    if (text.startsWith('"') || text.startsWith('{') || text.startsWith('[')) {
      try {
        return _plain(jsonDecode(text), depth + 1);
      } catch (_) {
        return _stripHtml(text);
      }
    }
    return _stripHtml(text);
  }
  if (raw is Map) {
    final map = raw.map((key, value) => MapEntry(key.toString(), value));
    for (final key in const ['paramValue', 'value', 'content', 'data']) {
      if (map.containsKey(key)) return _plain(map[key], depth + 1);
    }
    return '';
  }
  if (raw is List) {
    return [
      for (final item in raw)
        if (_plain(item, depth + 1).isNotEmpty) _plain(item, depth + 1),
    ].join('\n\n');
  }
  return '';
}

/// 剥掉 HTML 标签并还原常见实体，保留换行
String _stripHtml(String html) {
  var text = html
      .replaceAll(RegExp(r'<(script|style)[\s\S]*?</\1>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|li|h[1-6])>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&ldquo;', '“')
      .replaceAll('&rdquo;', '”');
  // 折叠多余空行
  text = text.replaceAll(RegExp(r'[ \t]+\n'), '\n');
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text;
}
