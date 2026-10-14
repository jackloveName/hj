import 'dart:convert';
import 'dart:typed_data';

// 只取「浏览器工厂」这一个入口：idb_shim 的默认入口会连带把内存实现
// （依赖 sembast）打进 Web 产物，白白多一百多 KB
import 'package:idb_shim/idb_client_native_interop.dart' show idbFactoryNative;
import 'package:shared_preferences/shared_preferences.dart';

import 'media_cache_name.dart';
import 'media_idb.dart';

/// Web 端媒体存储。
///
/// 主路径是 **IndexedDB**（配额大、能直接存二进制）；
/// 只有浏览器不支持 IndexedDB（老浏览器 / 无痕模式禁用）时，
/// 才回落到历史上的 localStorage 方案（约 5MB，写满会降级成会话内存）。
class MediaStore {
  MediaStore._(this._prefs, this._idb);

  /// 进程内缓存上限：浏览相册时别把整本相册留在内存里
  static const int _memoryLimit = 8;
  static const String _migratedKey = 'zudun.media.idb_migrated';
  static const String _localMediaPrefix = 'media:';
  static const String _localCloudPrefix = 'cloud:';

  final SharedPreferences _prefs;

  /// IndexedDB 后端；一旦发现「写进去读不回来」就置空，后续都走 localStorage
  IdbMediaBackend? _idb;
  final Map<String, Uint8List> _memory = <String, Uint8List>{};
  bool _lastWritePersisted = true;

  /// 浏览器存储容量不足时为 false：照片只存在于本次会话内存中，刷新后会丢失。
  bool get lastWritePersisted => _lastWritePersisted;

  static Future<MediaStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    IdbMediaBackend? idb;
    try {
      idb = IdbMediaBackend(idbFactoryNative);
      await _migrateFromLocalStorage(prefs, idb);
    } catch (_) {
      // 拿不到 IndexedDB 也别把功能弄挂：退回 localStorage 行为
      idb = null;
    }
    return MediaStore._(prefs, idb);
  }

  /// 老版本把照片存在 localStorage 里：搬到 IndexedDB，顺手把那 5MB 释放掉
  static Future<void> _migrateFromLocalStorage(
    SharedPreferences prefs,
    IdbMediaBackend idb,
  ) async {
    if (prefs.getBool(_migratedKey) == true) return;
    var allMoved = true;
    for (final key in prefs.getKeys().toList()) {
      if (!_isMediaKey(key)) continue;
      final encoded = prefs.getString(key);
      if (encoded == null) continue;
      try {
        final bytes = base64Decode(encoded);
        await idb.put(key, bytes);
        // 读回来核对一遍再删原件：万一 IndexedDB 存进去读不回，
        // localStorage 这份就是唯一的照片，绝不能先删
        final back = await idb.get(key);
        if (back == null || back.length != bytes.length) {
          allMoved = false;
          continue;
        }
        await prefs.remove(key);
      } catch (_) {
        // 这一条搬不动就留着，读取时会再试一次
        allMoved = false;
      }
    }
    if (allMoved) await prefs.setBool(_migratedKey, true);
  }

  static bool _isMediaKey(String key) =>
      key.startsWith(_localMediaPrefix) || key.startsWith(_localCloudPrefix);

  Future<String> saveBytes(
    Uint8List bytes, {
    required String folder,
    required String name,
  }) async {
    final key = 'media:$folder/$name';
    _remember(key, bytes);
    final idb = _idb;
    if (idb == null) {
      await _saveToPrefs(key, bytes);
      return key;
    }
    // 写完立刻读回来校验：个别浏览器 / 隐私模式下 IndexedDB 会「存进去读不回」，
    // 这时候退回 localStorage，宁可占那 5MB，也不能让照片凭空消失
    await _putVerified(idb, key, bytes);
    return key;
  }

  Future<Uint8List?> read(String ref) => _read(ref, _isMediaKey);

  Future<void> delete(String ref) => _delete(ref);

  String _cloudKey(String ref) => 'cloud:${cloudCacheName(ref)}';

  Future<void> saveCloudBytes(String ref, Uint8List bytes) async {
    if (ref.isEmpty) return;
    final key = _cloudKey(ref);
    _remember(key, bytes);
    final idb = _idb;
    if (idb == null) {
      await _saveToPrefs(key, bytes);
      return;
    }
    try {
      await idb.put(key, bytes);
    } catch (_) {
      // 与本地照片一致：写不进去就只在本次会话内可用
    }
  }

  /// 写 IndexedDB + 读回校验；不通过就退回 localStorage 并停用 IndexedDB
  Future<void> _putVerified(
    IdbMediaBackend idb,
    String key,
    Uint8List bytes,
  ) async {
    try {
      await idb.put(key, bytes);
      final back = await idb.get(key);
      if (back != null && back.length == bytes.length) {
        _lastWritePersisted = true;
        return;
      }
    } catch (_) {
      // 下面统一走回落
    }
    _idb = null;
    await _saveToPrefs(key, bytes);
  }

  Future<Uint8List?> readCloudBytes(String ref) =>
      ref.isEmpty ? Future.value(null) : _read(_cloudKey(ref), _isMediaKey);

  Future<void> deleteCloudBytes(String ref) async {
    if (ref.isEmpty) return;
    await _delete(_cloudKey(ref));
  }

  /// 真实占用：IndexedDB 里记的是字节长度；回落到 localStorage 时按 base64 长度估算
  Future<int> usedBytes() async {
    final idb = _idb;
    if (idb != null) {
      try {
        return await idb.totalBytes();
      } catch (_) {
        // 读不到就退化成估算
      }
    }
    var total = 0;
    for (final key in _prefs.getKeys()) {
      if (!_isMediaKey(key)) continue;
      final encoded = _prefs.getString(key);
      if (encoded == null) continue;
      total += (encoded.length * 3) ~/ 4;
    }
    return total;
  }

  // -------------------------------------------------------------------------
  // 内部
  // -------------------------------------------------------------------------

  Future<Uint8List?> _read(String key, bool Function(String) isMediaKey) async {
    if (key.isEmpty) return null;
    final cached = _memory.remove(key);
    if (cached != null) {
      _remember(key, cached); // 命中后移到队尾
      return cached;
    }
    final idb = _idb;
    if (idb != null) {
      try {
        final bytes = await idb.get(key);
        if (bytes != null) {
          _remember(key, bytes);
          return bytes;
        }
      } catch (_) {
        // 读失败当作没读到，下面再兜一层 localStorage
      }
    }
    // 迁移没成功的老数据仍可能留在 localStorage
    if (!isMediaKey(key)) return null;
    final encoded = _prefs.getString(key);
    if (encoded == null) return null;
    try {
      final bytes = base64Decode(encoded);
      _remember(key, bytes);
      if (idb != null) {
        try {
          await idb.put(key, bytes);
          await _prefs.remove(key);
        } catch (_) {
          // 搬不过去就继续留着，下次再试
        }
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _delete(String key) async {
    _memory.remove(key);
    final idb = _idb;
    if (idb != null) {
      try {
        await idb.delete(key);
      } catch (_) {
        // 删不掉也不阻塞流程，下面还会清 localStorage
      }
    }
    await _prefs.remove(key);
  }

  Future<void> _saveToPrefs(String key, Uint8List bytes) async {
    try {
      await _prefs.setString(key, base64Encode(bytes));
      _lastWritePersisted = true;
    } catch (_) {
      _lastWritePersisted = false;
    }
  }

  void _remember(String key, Uint8List bytes) {
    _memory.remove(key);
    _memory[key] = bytes;
    while (_memory.length > _memoryLimit) {
      _memory.remove(_memory.keys.first);
    }
  }
}
