import 'dart:typed_data';

import 'package:idb_shim/idb.dart';

/// IndexedDB 媒体仓库（Web 端主路径）。
///
/// 为什么不用 localStorage：照片按 base64 存进 localStorage 只有约 5MB 配额，
/// base64 还要膨胀 33%，两张原图就能写满；IndexedDB 的配额是磁盘级的，
/// 而且可以直接存二进制，省掉那 33% 的开销。
///
/// 这里不碰任何浏览器专有 API，工厂由外部注入（浏览器给 IndexedDB 工厂、
/// 测试给内存工厂），所以逻辑能在 VM 里跑单元测试。
class IdbMediaBackend {
  IdbMediaBackend(this._factory);

  static const String dbName = 'zudun_media';
  static const String mediaStore = 'media';
  static const String metaStore = 'meta';
  static const int dbVersion = 1;

  final IdbFactory _factory;
  Database? _db;

  Future<Database> _database() async {
    final cached = _db;
    if (cached != null) return cached;
    final opened = await _factory.openOnDowngradeDelete(
      dbName,
      version: dbVersion,
      onUpgradeNeeded: (event) {
        final db = event.database;
        if (!db.objectStoreNames.contains(mediaStore)) {
          db.createObjectStore(mediaStore);
        }
        if (!db.objectStoreNames.contains(metaStore)) {
          db.createObjectStore(metaStore);
        }
      },
    );
    _db = opened;
    return opened;
  }

  /// 写入一张照片（key 就是原来的 ref）
  Future<void> put(String key, Uint8List bytes) async {
    final db = await _database();
    final txn = db.transaction([mediaStore, metaStore], idbModeReadWrite);
    await txn.objectStore(mediaStore).put(bytes, key);
    // meta 里只存长度：统计占用时不用把照片全读出来
    await txn.objectStore(metaStore).put(bytes.length, key);
    await txn.completed;
  }

  Future<Uint8List?> get(String key) async {
    final db = await _database();
    final txn = db.transaction(mediaStore, idbModeReadOnly);
    final value = await txn.objectStore(mediaStore).getObject(key);
    await txn.completed;
    return asBytes(value);
  }

  Future<void> delete(String key) async {
    final db = await _database();
    final txn = db.transaction([mediaStore, metaStore], idbModeReadWrite);
    await txn.objectStore(mediaStore).delete(key);
    await txn.objectStore(metaStore).delete(key);
    await txn.completed;
  }

  /// 已占用字节数
  Future<int> totalBytes() async {
    final db = await _database();
    final txn = db.transaction(metaStore, idbModeReadOnly);
    final values = await txn.objectStore(metaStore).getAll();
    await txn.completed;
    var total = 0;
    for (final value in values) {
      if (value is int) total += value;
    }
    return total;
  }

  void close() {
    _db?.close();
    _db = null;
  }

  /// 浏览器取回来的是 Uint8List；内存实现（测试）取回来还是 Dart 对象。
  static Uint8List? asBytes(Object? value) {
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    if (value is List) {
      final bytes = <int>[];
      for (final item in value) {
        if (item is int) bytes.add(item);
      }
      return bytes.isEmpty ? null : Uint8List.fromList(bytes);
    }
    return null;
  }
}
