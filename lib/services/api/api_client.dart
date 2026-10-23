import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 接口异常：message 可直接展示给用户。
class ApiException implements Exception {
  ApiException(
    this.message, {
    this.code = '',
    this.unauthorized = false,
    this.reachable = true,
    this.notify = true,
  });

  final String message;

  /// 业务响应码（00000 / A00001 …）；网络层错误为空串。
  final String code;

  /// 登录态失效：调用方应清理 Token 并回到登录页。
  final bool unauthorized;

  /// false 表示请求没能到达服务端（超时 / 断网）。
  final bool reachable;

  /// 是否适合用 Toast 提示用户（silent 请求为 false）。
  final bool notify;

  @override
  String toString() => message;
}

/// 按平台网关约定解析响应体，返回解包后的数据。
///
/// - `00000` → 取 `data` 字段；
/// - `200` / 无 `code` → 返回整个响应体；
/// - `401` / `000401` / `A000401` / `msg=unauthorized` → 登录失效；
/// - `A00001` / `A00005` / `A00006` 及其它非 200 → 抛出业务错误。
Object? resolveApiResponse({
  required int statusCode,
  required Object? body,
  bool silent = false,
}) {
  final Map<String, dynamic> map = body is Map
      ? body.map((key, value) => MapEntry(key.toString(), value))
      : <String, dynamic>{};
  final hasCode = map.containsKey('code');
  final code = '${map['code'] ?? 200}';
  final message = '${map['msg'] ?? map['message'] ?? ''}'.trim();

  final unauthorized =
      statusCode == 401 ||
      code == '401' ||
      code == '000401' ||
      code == 'A000401' ||
      message.toLowerCase() == 'unauthorized';
  if (unauthorized) {
    throw ApiException('登录已失效，请重新登录', code: code, unauthorized: true);
  }

  if (statusCode >= 400 && !hasCode) {
    throw ApiException(
      '请求失败（$statusCode）',
      code: '$statusCode',
      notify: !silent,
    );
  }

  if (code == '00000') return map['data'];
  if (code == 'A00001' || code == 'A00005' || code == 'A00006') {
    throw ApiException(
      message.isEmpty ? '请求失败' : message,
      code: code,
      notify: !silent,
    );
  }
  if (code != '200') {
    throw ApiException(
      message.isEmpty ? code : message,
      code: code,
      notify: !silent,
    );
  }
  return map.isNotEmpty ? map : body;
}

/// 统一请求封装：拼接网关地址、附带 Token、按约定解析响应。
class ApiClient {
  ApiClient({
    required this.baseUrl,
    this.tokenProvider,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 10),
    this.onUnauthorized,
  }) : _http = httpClient ?? http.Client();

  /// 网关地址（可在「我的 → 设置 → 服务器地址」里修改）
  String baseUrl;

  /// 读取当前 Token（未登录时返回空串）
  String Function()? tokenProvider;

  final Duration timeout;
  final http.Client _http;

  /// 收到 401 时回调一次，用于清理登录态
  void Function()? onUnauthorized;

  void close() => _http.close();

  Future<Object?> get(
    String path, {
    Map<String, Object?>? params,
    bool needToken = true,
    bool silent = false,
    Duration? timeout,
  }) => send(
    path,
    method: 'GET',
    params: params,
    needToken: needToken,
    silent: silent,
    timeout: timeout,
  );

  Future<Object?> post(
    String path, {
    Object? data,
    bool needToken = true,
    bool silent = false,
    Duration? timeout,
  }) => send(
    path,
    method: 'POST',
    data: data,
    needToken: needToken,
    silent: silent,
    timeout: timeout,
  );

  Future<Object?> put(
    String path, {
    Object? data,
    bool needToken = true,
    bool silent = false,
    Duration? timeout,
  }) => send(
    path,
    method: 'PUT',
    data: data,
    needToken: needToken,
    silent: silent,
    timeout: timeout,
  );

  Future<Object?> send(
    String path, {
    String method = 'GET',
    Map<String, Object?>? params,
    Object? data,
    bool needToken = true,
    bool silent = false,
    Duration? timeout,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: params == null || params.isEmpty
          ? null
          : {
              for (final entry in params.entries)
                if (entry.value != null) entry.key: '${entry.value}',
            },
    );
    final headers = <String, String>{
      if (data != null) 'Content-Type': 'application/json; charset=utf-8',
    };
    final token = needToken ? (tokenProvider?.call() ?? '') : '';
    if (token.isNotEmpty) headers['Authorization'] = token;

    http.Response response;
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (data != null) {
        request.bodyBytes = utf8.encode(jsonEncode(data));
      }
      final streamed = await _http
          .send(request)
          .timeout(timeout ?? this.timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiException('请求超时，请稍后重试', reachable: false, notify: !silent);
    } catch (error) {
      throw ApiException('网络连接失败，请检查网络', reachable: false, notify: !silent);
    }

    Object? body;
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (text.isNotEmpty) {
      try {
        body = jsonDecode(text);
      } catch (_) {
        body = text;
      }
    }

    try {
      return resolveApiResponse(
        statusCode: response.statusCode,
        body: body,
        silent: silent,
      );
    } on ApiException catch (error) {
      if (error.unauthorized) onUnauthorized?.call();
      rethrow;
    }
  }

  /// OSS 预签名直传：不做鉴权，也不解析业务响应码。
  Future<void> putBytes(
    String url,
    List<int> bytes, {
    required String contentType,
  }) async {
    try {
      final response = await _http
          .put(
            Uri.parse(url),
            headers: {'Content-Type': contentType},
            body: bytes,
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException('图片上传失败（${response.statusCode}）');
      }
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('图片上传超时，请稍后重试', reachable: false);
    } catch (error) {
      throw ApiException('图片上传失败：$error', reachable: false);
    }
  }

  /// 下载文件（照片 / 缩略图）
  Future<List<int>> getBytes(String url) async {
    try {
      final response = await _http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException('图片下载失败（${response.statusCode}）');
      }
      return response.bodyBytes;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('图片下载超时', reachable: false);
    } catch (error) {
      throw ApiException('图片下载失败：$error', reachable: false);
    }
  }
}
