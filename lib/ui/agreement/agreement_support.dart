import 'dart:convert';

/// agreement 页面与 H5/threeweb-view 共用的 URL、消息解析规则。
class AgreementSupport {
  AgreementSupport._();

  static bool isSafeWebUrl(String? value) {
    final uri = Uri.tryParse((value ?? '').trim());
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  static bool isExternalUrl(String value) {
    return RegExp(
      r'apps\.apple\.com|open_external=true|\.(?:apk|plist)(?:$|[?#])',
      caseSensitive: false,
    ).hasMatch(value);
  }

  static String buildEntryUrl({
    required String baseUrl,
    required String token,
    required String appName,
    required double statusHeight,
    double? longitude,
    double? latitude,
  }) {
    final base = Uri.parse(baseUrl.trim());
    final query = <String, String>{...base.queryParameters};
    void add(String key, String? value) {
      final text = value?.trim() ?? '';
      if (text.isNotEmpty) query[key] = text;
    }

    add('token', token);
    add('statusHeight', '$statusHeight');
    add('appName', appName);
    add('longitude', longitude?.toString());
    add('latitude', latitude?.toString());
    return base.replace(queryParameters: query).toString();
  }

  /// 兼容 uni-app web-view 的 `{data/arg.data}`、数组和 JSON 字符串形态。
  static Map<String, dynamic>? messagePayload(String raw) {
    dynamic value;
    try {
      value = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    for (var depth = 0; depth < 4; depth++) {
      if (value is List && value.isNotEmpty) {
        value = value.first;
        continue;
      }
      if (value is String) {
        try {
          value = jsonDecode(value);
          continue;
        } catch (_) {
          return null;
        }
      }
      if (value is! Map) return null;
      final map = value.map((key, value) => MapEntry('$key', value));
      // uni.webview.js 在普通 H5 WebView 中的标准投递格式。
      if (map['type'] == 'WEB_INVOKE_APPSERVICE') {
        final envelope = map['data'];
        if (envelope is! Map || envelope['name'] != 'postMessage') return null;
        value = envelope['arg'];
        continue;
      }
      final arg = map['arg'];
      if (arg is Map && arg['data'] != null) {
        value = arg['data'];
        continue;
      }
      if (map['data'] != null) {
        value = map['data'];
        continue;
      }
      return map;
    }
    return null;
  }
}
