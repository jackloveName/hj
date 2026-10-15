import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/local_store.dart';

/// 一条错误记录
class ErrorEntry {
  const ErrorEntry({
    required this.time,
    required this.message,
    this.detail = '',
  });

  final DateTime time;
  final String message;
  final String detail;

  Map<String, dynamic> toJson() => {
    'time': time.toIso8601String(),
    'message': message,
    'detail': detail,
  };

  static ErrorEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final time = DateTime.tryParse('${raw['time']}');
    if (time == null) return null;
    return ErrorEntry(
      time: time,
      message: '${raw['message'] ?? ''}',
      detail: '${raw['detail'] ?? ''}',
    );
  }

  String get line {
    final stamp = time.toIso8601String().split('.').first;
    return detail.isEmpty ? '$stamp  $message' : '$stamp  $message\n$detail';
  }
}

/// 本机错误日志：没有接崩溃上报服务时，至少让用户能把出错信息发给我们。
///
/// - 只留最近 [maxEntries] 条，避免无限增长
/// - 落在本机存储里（Web 是 localStorage，移动端是 SharedPreferences）
class ErrorLog extends ChangeNotifier {
  ErrorLog(this._store);

  static const String _key = 'zudun.error_log';
  static const int maxEntries = 50;

  final LocalStore _store;
  final List<ErrorEntry> _entries = <ErrorEntry>[];
  bool _loaded = false;

  List<ErrorEntry> get entries => List.unmodifiable(_entries.reversed);
  bool get isEmpty => _entries.isEmpty;

  void load() {
    if (_loaded) return;
    _loaded = true;
    final raw = _store.getString(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _entries
          ..clear()
          ..addAll(decoded.map(ErrorEntry.fromJson).whereType<ErrorEntry>());
      }
    } catch (_) {
      _entries.clear();
    }
    notifyListeners();
  }

  /// 记一条（同步接口，出错时也能马上落盘）
  void add(Object error, {StackTrace? stack, String? note}) {
    final message = note == null ? '$error' : '$note：$error';
    _entries.add(
      ErrorEntry(
        time: DateTime.now(),
        message: message,
        detail: stack?.toString().split('\n').take(6).join('\n') ?? '',
      ),
    );
    while (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }
    unawaited(_persist());
    notifyListeners();
  }

  Future<void> clear() async {
    _entries.clear();
    await _store.remove(_key);
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      await _store.setString(
        _key,
        jsonEncode([for (final entry in _entries) entry.toJson()]),
      );
    } catch (_) {
      // 记日志本身失败就算了，不能反过来把 App 弄崩
    }
  }

  /// 全量文本，供用户复制发给客服
  String get text => isEmpty
      ? '暂无错误记录'
      : _entries.reversed.map((entry) => entry.line).join('\n\n');

  /// 接上 Flutter / 异步错误：在 main 里调用一次
  void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      add(
        details.exception,
        stack: details.stack,
        note: 'Flutter 异常',
      );
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      add(error, stack: stack, note: '未捕获异常');
      return true;
    };
  }
}
